///|
/// Analytic Rasterizer。セルバッファに area-cover パック値を蓄積し、
/// prefix sum sweep でカバレッジマスクを生成する。
/// 上流 `raster/analytic.rs` の移植。
///
/// ## セルエンコーディング (Blend2D / AGG 方式)
///
/// 1 セルあたり i32 1 個に cover と area をパックして格納する:
///
/// ```text
/// cells[x]   += cover * 512 - area
/// cells[x+1] += area
/// ```
///
/// - `cover` = エッジの Y 方向通過量 × 256 × direction
/// - `area`  = (fx_start + fx_end) × dy × 65536 × direction
///
/// sweep 時は `min(abs(cover_acc >> 9), 255)` で 0-255 カバレッジに変換する。

///|
/// スキャンライン処理に必要なコンテキスト。上流 ScanlineCtx に対応。
priv struct ScanlineCtx {
  mut top : Double
  mut bottom : Double
  clip_x0 : Int32
  /// dirty 範囲の下限 (書き込んだセルの最小インデックス)。
  mut dirty_min : Int32
  /// dirty 範囲の上限 (書き込んだセルの最大インデックス + 1)。
  /// cells[x+1] 書き込みにより width+1 に達し得る。
  mut dirty_max : Int32
  /// エッジの X 座標がセルバッファの右端を超えた場合に true。
  /// 閉じる側の delta が書き込まれないため、prefix sum が 0 に戻らない。
  /// この場合は sweep 範囲を width まで拡張する必要がある。
  mut right_clipped : Bool
}

///|
/// Analytic Rasterizer の本体。呼び出し間でバッファを再利用する。
pub struct AnalyticRasterizer {
  /// area-cover パック値のセルバッファ。幅 + 1 要素 (area スピルオーバー用)。
  mut cells : Array[Int32]
  /// sweep 結果のカバレッジマスク。
  mut cov_buf : Array[Byte]
  /// Y ソート用バッファ。呼び出し間で再利用する。
  sorted_buf : Array[(Double, Double, Double, Double)]
}

///|
pub fn AnalyticRasterizer::new() -> AnalyticRasterizer {
  { cells: [], cov_buf: [], sorted_buf: [], }
}

///|
/// 上流の Vec::resize と同じく、既存の値を保持したまま長さを変更する。
/// 縮小時は末尾を切り捨てる。ラスタライザは sweep 時に読んだセルを
/// ゼロクリアする設計のため、ここでは全面クリアしない。
fn resize_preserve(arr : Array[Int32], n : Int32) -> Array[Int32] {
  if arr.length() == n {
    arr
  } else {
    let out = Array::make(n, 0)
    let limit = @cmp.minimum(arr.length(), n)
    for i in 0..<limit {
      out[i] = arr[i]
    }
    out
  }
}

///|
/// エッジ群をラスタライズし、スキャンラインごとにコールバックを呼ぶ。
///
/// コールバック `f(y, x_start, coverage)` は非ゼロカバレッジ区間に対して呼ばれる。
/// `even_odd` が true のとき EvenOdd 規則、false のとき NonZero 規則で変換する。
pub fn AnalyticRasterizer::rasterize(
  self : AnalyticRasterizer,
  edges : Array[(Double, Double, Double, Double)],
  clip_x0 : Int32,
  clip_y0 : Int32,
  clip_x1 : Int32,
  clip_y1 : Int32,
  even_odd~ : Bool = false,
  f : (Int32, Int32, ArrayView[Byte]) -> Unit,
) -> Unit {
  let width = clip_x1 - clip_x0
  if width <= 0 {
    return
  }

  // cells[x+1] 書き込みのため 1 要素余分に確保する
  self.cells = resize_preserve(self.cells, width + 1)
  if self.cov_buf.length() < width {
    self.cov_buf = Array::make(width, b'\x00')
  }

  // エッジを Y の最小値でソートする (再使用バッファ)
  let sorted = self.sorted_buf
  sorted.clear()
  for e in edges {
    sorted.push(e)
  }
  sorted.sort_by(fn(a, b) {
    Double::compare(@cmp.minimum(a.1, a.3), @cmp.minimum(b.1, b.3))
  })

  // 完了済みエッジをスキップするインデックス
  let mut next_edge_idx = 0

  let ctx : ScanlineCtx = {
    top: 0.0,
    bottom: 0.0,
    clip_x0,
    dirty_min: width + 1,
    dirty_max: 0,
    right_clipped: false,
  }

  for y in clip_y0..<clip_y1 {
    ctx.top = y.to_double()
    ctx.bottom = (y + 1).to_double()

    // セルのゼロクリアは sweep 関数内で読み取り直後に行う (Blend2D 方式)。
    // sweep で処理されなかったセルはここでクリアが必要。
    // dirty_max が width+1 に達する cells[x+1] のスピルオーバーのみ残る。
    if ctx.dirty_max > width && ctx.dirty_max <= width + 1 {
      self.cells[width] = 0
    }
    ctx.dirty_min = width + 1
    ctx.dirty_max = 0
    ctx.right_clipped = false

    // scanline_top 以下で完了しているエッジをスキップする
    while next_edge_idx < sorted.length() {
      let e = sorted[next_edge_idx]
      let y_max = @cmp.maximum(e.1, e.3)
      if y_max > ctx.top {
        break
      }
      next_edge_idx += 1
    }

    // next_edge_idx からイテレートし、y_min >= scanline_bottom で打ち切る
    for i in next_edge_idx..<sorted.length() {
      let e = sorted[i]
      let y_min = @cmp.minimum(e.1, e.3)
      if y_min >= ctx.bottom {
        break
      }
      self.add_edge(e.0, e.1, e.2, e.3, ctx)
    }

    // sweep してカバレッジマスクを生成する。
    // dirty_min..dirty_max は非ゼロ delta が書かれた範囲。
    // sweep は可視ピクセル範囲 (0..width) に限定する。
    // dirty_max は cells[x+1] 書き込みにより width+1 に達し得るが、
    // sweep_max は width を超えない。
    // ただしエッジが画像右端でクリップされた場合 (right_clipped=true)、
    // 閉じる側の delta が失われるため sweep_max を width まで拡張する。
    let sweep_dirty_min = @cmp.minimum(ctx.dirty_min, width)
    if sweep_dirty_min < ctx.dirty_max {
      let sweep_max = if ctx.right_clipped {
        width
      } else {
        @cmp.minimum(ctx.dirty_max, width)
      }
      if sweep_dirty_min < sweep_max {
        self.sweep(sweep_dirty_min, sweep_max, even_odd)

        // 非ゼロ範囲を検出する
        let mut first = -1
        let mut last = -1
        for i in sweep_dirty_min..<sweep_max {
          if self.cov_buf[i] != b'\x00' {
            if first < 0 {
              first = i
            }
            last = i
          }
        }
        if first >= 0 {
          let span_end = last + 1
          f(y, clip_x0 + first, self.cov_buf[first:span_end])
        }
      }
    }
  }
}

///|
/// dirty 範囲に限定した prefix sum sweep。
/// セルを読み取った直後にゼロクリアする (上流の JIT sweep と同じ契約)。
fn AnalyticRasterizer::sweep(
  self : AnalyticRasterizer,
  start : Int32,
  end : Int32,
  even_odd : Bool,
) -> Unit {
  let mut cover = 0
  for i in start..<end {
    cover += self.cells[i]
    self.cells[i] = 0
    // 算術右シフト 9。MoonBit の Int >> は算術シフト。
    let shifted = cover >> 9
    let abs = if shifted < 0 { -shifted } else { shifted }
    let v = if even_odd {
      // 2 winding 周期 (= 512) で折り返す
      let val = abs & 511
      @cmp.minimum(@cmp.minimum(val, 512 - val), 255)
    } else {
      @cmp.minimum(abs, 255)
    }
    self.cov_buf[i] = v.to_byte()
  }
}

///|
/// セルバッファに area-cover パック値を書き込む。
///
/// idx が範囲外の場合:
/// - idx < 0: 左クリップ。cover 寄与を cells[0] に繰り越す。
/// - idx >= cells.length(): 右クリップ。right_clipped フラグを立てる。
fn AnalyticRasterizer::write_cell(
  self : AnalyticRasterizer,
  idx : Int32,
  value : Int32,
  ctx : ScanlineCtx,
) -> Unit {
  if idx >= 0 && idx < self.cells.length() {
    self.cells[idx] += value
    if idx < ctx.dirty_min {
      ctx.dirty_min = idx
    }
    if idx + 1 > ctx.dirty_max {
      ctx.dirty_max = idx + 1
    }
  } else if idx < 0 {
    // 左クリップ: 値を cells[0] に繰り越す
    self.cells[0] += value
    if 0 < ctx.dirty_min {
      ctx.dirty_min = 0
    }
    if 1 > ctx.dirty_max {
      ctx.dirty_max = 1
    }
  } else {
    ctx.right_clipped = true
  }
}

///|
/// 1 セル分の area-cover パック値を計算してセルバッファに書き込む。
///
/// `x_start`, `x_end` はセル内のエッジ端点 (ピクセル座標)。
/// `y_start`, `y_end` はスキャンライン内のクリップ済み Y 座標。
fn AnalyticRasterizer::emit_cell(
  self : AnalyticRasterizer,
  cell_x : Int32,
  x_start : Double,
  x_end : Double,
  y_start : Double,
  y_end : Double,
  direction_sign : Int32,
  ctx : ScanlineCtx,
) -> Unit {
  let fx_start = x_start - cell_x.to_double()
  let fx_end = x_end - cell_x.to_double()
  let dy = y_end - y_start

  // cover: 整数累積方式で計算する。
  // (dy * 256.0) as i32 をセルごとに独立計算すると切り捨て誤差が蓄積し、
  // 複数セルにまたがるエッジの cover 合計が正確な値より小さくなる。
  // y_start, y_end を個別に量子化してその差を取ることで、
  // セル分割した cover の合計が常にエッジ全体の cover と一致する。
  let cover = (f64_to_i32_sat(y_end * 256.0) - f64_to_i32_sat(y_start * 256.0)) *
    direction_sign
  let area = f64_to_i32_sat((fx_start + fx_end) * dy * 65536.0) * direction_sign

  let delta = cover * 512 - area
  let idx = cell_x - ctx.clip_x0

  self.write_cell(idx, delta, ctx)
  self.write_cell(idx + 1, area, ctx)
}

///|
/// Rust の `f64 as i32` 相当の飽和変換。
/// NaN → 0、範囲外 → i32::MIN/MAX に飽和する。
fn f64_to_i32_sat(x : Double) -> Int32 {
  if x.is_nan() {
    0
  } else if x >= 2147483647.0 {
    2147483647
  } else if x <= -2147483648.0 {
    -2147483648
  } else {
    x.to_int()
  }
}

///|
/// 1 本の線分がスキャンラインと交差する部分の area-cover パック値を
/// セルバッファに書き込む。
///
/// エッジが複数セルをまたぐ場合、整数 X 境界で分割して各セルに emit_cell を呼ぶ。
fn AnalyticRasterizer::add_edge(
  self : AnalyticRasterizer,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  ctx : ScanlineCtx,
) -> Unit {
  // 水平線はスキップ (cover に寄与しない)
  if y0 == y1 {
    return
  }

  // Y 方向にクリップ
  let (ey0, ey1) = if y0 < y1 { (y0, y1) } else { (y1, y0) }
  if ey1 <= ctx.top || ey0 >= ctx.bottom {
    return
  }

  // 方向: 下向き (y0 < y1) = +1, 上向き (y0 > y1) = -1
  let direction_sign = if y0 < y1 { 1 } else { -1 }

  // このスキャンラインでクリップされた Y 範囲
  let clipped_top = @cmp.maximum(ey0, ctx.top)
  let clipped_bottom = @cmp.minimum(ey1, ctx.bottom)

  // クリップ後の X 座標を計算する。
  // y0 != y1 は上で確認済みなので dy_total は非ゼロ。
  // 2 回の除算を 1 回の除算 + 2 回の乗算に置換する。
  let dy_total = y1 - y0
  let dx_total = x1 - x0
  let inv_dy_total = 1.0 / dy_total
  let t_top = (clipped_top - y0) * inv_dy_total
  let t_bot = (clipped_bottom - y0) * inv_dy_total
  let x_at_top = x0 + t_top * dx_total
  let x_at_bot = x0 + t_bot * dx_total

  // 単一セル判定
  let ex_top = f64_to_i32_sat(x_at_top.floor())
  let ex_bot = f64_to_i32_sat(x_at_bot.floor())

  if ex_top == ex_bot {
    // 単一セル: cover と area を計算して書き込み
    self.emit_cell(
      ex_top, x_at_top, x_at_bot, clipped_top, clipped_bottom, direction_sign, ctx,
    )
    return
  }

  // 複数セル: 整数 X 境界で分割
  let dx = x_at_bot - x_at_top
  let dy = clipped_bottom - clipped_top
  let slope_y_per_x = if dx.abs() > 0.000000000001 { dy / dx } else { 0.0 }

  let mut x_cur = x_at_top
  let mut y_cur = clipped_top

  if dx > 0.0 {
    // 右方向に走査
    for cell_x in ex_top..<=ex_bot {
      let x_next = if cell_x == ex_bot {
        x_at_bot
      } else {
        (cell_x + 1).to_double()
      }
      let y_next = clipped_top + (x_next - x_at_top) * slope_y_per_x
      self.emit_cell(cell_x, x_cur, x_next, y_cur, y_next, direction_sign, ctx)
      x_cur = x_next
      y_cur = y_next
    }
  } else {
    // 左方向に走査 (上流は (ex_bot..=ex_top).rev() = 降順)
    for cell_x = ex_top; cell_x >= ex_bot; cell_x = cell_x - 1 {
      let x_next = if cell_x == ex_bot { x_at_bot } else { cell_x.to_double() }
      let y_next = clipped_top + (x_next - x_at_top) * slope_y_per_x
      self.emit_cell(cell_x, x_cur, x_next, y_cur, y_next, direction_sign, ctx)
      x_cur = x_next
      y_cur = y_next
    }
  }
}
