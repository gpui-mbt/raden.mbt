///|
/// 2D パス。コマンド列と点列で構成される。
/// 上流 `api/path.rs` の `Path` に対応。
///
/// 上流で panic/assert になっていた入力エラー
/// (smooth_* の前置条件違反、conic の非正の重み) は
/// `RadenError::InvalidInput` を返すように変更している
/// (`docs/known-differences.md` 参照)。

///|
/// パスコマンドの種別。
pub(all) enum PathCmd {
  MoveTo
  LineTo
  /// 2 点消費 (cp, end)。
  QuadTo
  /// 有理二次ベジェ (円錐曲線)。2 点消費 (制御点, 終点) + `conic_weights` の対応する重み。
  ConicTo
  /// 3 点消費 (cp1, cp2, end)。
  CubicTo
  Close
} derive(Eq, Debug)

///|
/// Blend2D と同一の KAPPA 定数。円を 4 本の cubic Bezier で近似する係数。
let kappa : Double = 0.552_284_749_831

///|
/// パス本体。
pub struct Path {
  priv cmds : Array[PathCmd]
  priv points : Array[Point]
  /// `PathCmd::ConicTo` ごとの重み w (>= 0)。
  priv conic_weights : Array[Double]
  /// 現在点 (最後の `move_to` / `line_to` 等の終点)。
  priv mut cur : Point
  /// 現在のサブパスの開始点。
  priv mut sub_start : Point
  /// `smooth_quad_to` 用: 直前の二次ベジェの制御点。
  priv mut last_quad_cp : Point?
  /// `smooth_cubic_to` 用: 直前の三次ベジェの第 2 制御点。
  priv mut last_cubic_cp2 : Point?
}

///|
pub fn Path::new() -> Path {
  {
    cmds: [],
    points: [],
    conic_weights: [],
    cur: { x: 0.0, y: 0.0, },
    sub_start: { x: 0.0, y: 0.0, },
    last_quad_cp: None,
    last_cubic_cp2: None,
  }
}

///|
/// `PathCmd::ConicTo` に対応する重み列 (読み取り専用)。
pub fn Path::conic_weights(self : Path) -> ArrayView[Double] {
  self.conic_weights[:]
}

///|
pub fn Path::clear(self : Path) -> Unit {
  self.cmds.clear()
  self.points.clear()
  self.conic_weights.clear()
  self.last_quad_cp = None
  self.last_cubic_cp2 = None
}

///|
pub fn Path::is_empty(self : Path) -> Bool {
  self.cmds.is_empty()
}

///|
/// コマンド数を返す。
pub fn Path::length(self : Path) -> Int32 {
  self.cmds.length()
}

///|
pub fn Path::cmds(self : Path) -> ArrayView[PathCmd] {
  self.cmds[:]
}

///|
pub fn Path::points(self : Path) -> ArrayView[Point] {
  self.points[:]
}

///|
pub fn Path::move_to(self : Path, x : Double, y : Double) -> Unit {
  self.cmds.push(MoveTo)
  let p : Point = { x, y, }
  self.points.push(p)
  self.cur = p
  self.sub_start = p
  self.last_quad_cp = None
  self.last_cubic_cp2 = None
}

///|
pub fn Path::line_to(self : Path, x : Double, y : Double) -> Unit {
  self.cmds.push(LineTo)
  let p : Point = { x, y, }
  self.points.push(p)
  self.cur = p
  self.last_quad_cp = None
  self.last_cubic_cp2 = None
}

///|
/// 3 次ベジェ曲線を追加する。cp1, cp2 は制御点、x/y は終点。
pub fn Path::cubic_to(
  self : Path,
  cp1x : Double,
  cp1y : Double,
  cp2x : Double,
  cp2y : Double,
  x : Double,
  y : Double,
) -> Unit {
  self.cmds.push(CubicTo)
  self.points.push({ x: cp1x, y: cp1y, })
  let cp2 : Point = { x: cp2x, y: cp2y, }
  self.points.push(cp2)
  let end : Point = { x, y, }
  self.points.push(end)
  self.last_cubic_cp2 = Some(cp2)
  self.last_quad_cp = None
  self.cur = end
}

///|
/// 2 次ベジェ曲線を追加する。cp は制御点、x/y は終点。
pub fn Path::quad_to(
  self : Path,
  cpx : Double,
  cpy : Double,
  x : Double,
  y : Double,
) -> Unit {
  self.cmds.push(QuadTo)
  let cp : Point = { x: cpx, y: cpy, }
  self.points.push(cp)
  let end : Point = { x, y, }
  self.points.push(end)
  self.last_quad_cp = Some(cp)
  self.last_cubic_cp2 = None
  self.cur = end
}

///|
/// 前の二次ベジェの制御点を反射したスムーズ二次ベジェ。
/// 直前が `quad_to` でない場合は `InvalidInput` (上流は panic)。
pub fn Path::smooth_quad_to(
  self : Path,
  x : Double,
  y : Double,
) -> Unit raise RadenError {
  match self.last_quad_cp {
    None => raise InvalidInput("smooth_quad_to requires a preceding quad_to")
    Some(cp) => {
      let cpx = 2.0 * self.cur.x - cp.x
      let cpy = 2.0 * self.cur.y - cp.y
      self.quad_to(cpx, cpy, x, y)
    }
  }
}

///|
/// 前の三次ベジェの第 2 制御点を反射したスムーズ三次ベジェ。
/// 直前が `cubic_to` でない場合は `InvalidInput` (上流は panic)。
pub fn Path::smooth_cubic_to(
  self : Path,
  cp2x : Double,
  cp2y : Double,
  x : Double,
  y : Double,
) -> Unit raise RadenError {
  match self.last_cubic_cp2 {
    None => raise InvalidInput("smooth_cubic_to requires a preceding cubic_to")
    Some(cp2_prev) => {
      let cp1x = 2.0 * self.cur.x - cp2_prev.x
      let cp1y = 2.0 * self.cur.y - cp2_prev.y
      self.cubic_to(cp1x, cp1y, cp2x, cp2y, x, y)
    }
  }
}

///|
/// 円錐曲線 (有理二次ベジェ)。重み w > 0。
/// w <= 0 の場合は `InvalidInput` (上流は assert panic)。
pub fn Path::conic_to(
  self : Path,
  cx : Double,
  cy : Double,
  ex : Double,
  ey : Double,
  w : Double,
) -> Unit raise RadenError {
  if w <= 0.0 {
    raise InvalidInput("conic weight must be positive")
  }
  self.cmds.push(ConicTo)
  self.points.push({ x: cx, y: cy, })
  let end : Point = { x: ex, y: ey, }
  self.points.push(end)
  self.conic_weights.push(w)
  self.last_quad_cp = None
  self.last_cubic_cp2 = None
  self.cur = end
}

///|
/// 中心 (cx, cy)、半径 rx, ry、開始角・掃引角 (ラジアン) の楕円弧を
/// 現在点から接続する。
/// `force_move_to` が true のとき弧の始点へ `move_to`、false のとき `line_to` で接続する。
pub fn Path::arc_to(
  self : Path,
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
  start : Double,
  sweep : Double,
  force_move_to : Bool,
) -> Unit {
  if rx <= 0.0 || ry <= 0.0 || sweep == 0.0 {
    return
  }
  let sx = cx + rx * @math.cos(start)
  let sy = cy + ry * @math.sin(start)
  if force_move_to {
    self.move_to(sx, sy)
  } else {
    self.line_to(sx, sy)
  }
  add_arc_segments(self, cx, cy, rx, ry, start, sweep)
}

///|
pub fn Path::close(self : Path) -> Unit {
  self.cmds.push(Close)
  self.cur = self.sub_start
  self.last_quad_cp = None
  self.last_cubic_cp2 = None
}

///|
/// 扇形 (pie) を追加する。中心→弧→中心の閉じたパス。
///
/// - `(cx, cy)`: 中心
/// - `(rx, ry)`: X/Y 方向の半径
/// - `start`: 開始角度 (ラジアン)
/// - `sweep`: 掃引角度 (ラジアン)
pub fn Path::add_pie(
  self : Path,
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
  start : Double,
  sweep : Double,
) -> Unit {
  if rx <= 0.0 || ry <= 0.0 || sweep == 0.0 {
    return
  }

  // 中心から開始点への線
  let start_x = cx + rx * @math.cos(start)
  let start_y = cy + ry * @math.sin(start)
  self.move_to(cx, cy)
  self.line_to(start_x, start_y)

  // 円弧を cubic Bézier セグメントで近似して追加
  add_arc_segments(self, cx, cy, rx, ry, start, sweep)

  self.close()
}

///|
/// すべての頂点を `(dx, dy)` だけ平行移動する。`cur` / `sub_start` も同期する。
pub fn Path::translate(self : Path, dx : Double, dy : Double) -> Unit {
  for p in self.points {
    p.x += dx
    p.y += dy
  }
  self.cur.x += dx
  self.cur.y += dy
  self.sub_start.x += dx
  self.sub_start.y += dy
  match self.last_quad_cp {
    Some(p) => {
      p.x += dx
      p.y += dy
    }
    None => ()
  }
  match self.last_cubic_cp2 {
    Some(p) => {
      p.x += dx
      p.y += dy
    }
    None => ()
  }
}

///|
/// すべての頂点に行列を適用する。
/// コニックの重み (w) はアフィン変換で不変なので変更しない。
pub fn Path::transform(self : Path, m : Matrix2D) -> Unit {
  for p in self.points {
    let (x, y) = m.map_point(p.x, p.y)
    p.x = x
    p.y = y
  }
  let (cx, cy) = m.map_point(self.cur.x, self.cur.y)
  self.cur = { x: cx, y: cy, }
  let (sx, sy) = m.map_point(self.sub_start.x, self.sub_start.y)
  self.sub_start = { x: sx, y: sy, }
  match self.last_quad_cp {
    Some(p) => {
      let (x, y) = m.map_point(p.x, p.y)
      self.last_quad_cp = Some({ x, y, })
    }
    None => ()
  }
  match self.last_cubic_cp2 {
    Some(p) => {
      let (x, y) = m.map_point(p.x, p.y)
      self.last_cubic_cp2 = Some({ x, y, })
    }
    None => ()
  }
}

///|
/// 別の Path のコマンド/頂点列をこの Path に追加する。
///
/// 内部状態 (`cur` / `sub_start` / `last_*`) も自然に更新されるよう、
/// コマンドを 1 つずつ replay する実装を取る (上流と同じ)。
pub fn Path::add_path(self : Path, other : Path) -> Unit raise RadenError {
  if other.is_empty() {
    return
  }
  let mut pi = 0
  let mut wi = 0
  for cmd in other.cmds {
    match cmd {
      MoveTo => {
        let p = other.points[pi]
        pi += 1
        self.move_to(p.x, p.y)
      }
      LineTo => {
        let p = other.points[pi]
        pi += 1
        self.line_to(p.x, p.y)
      }
      QuadTo => {
        let cp = other.points[pi]
        let end = other.points[pi + 1]
        pi += 2
        self.quad_to(cp.x, cp.y, end.x, end.y)
      }
      ConicTo => {
        let cp = other.points[pi]
        let end = other.points[pi + 1]
        pi += 2
        let w = other.conic_weights[wi]
        wi += 1
        self.conic_to(cp.x, cp.y, end.x, end.y, w)
      }
      CubicTo => {
        let cp1 = other.points[pi]
        let cp2 = other.points[pi + 1]
        let end = other.points[pi + 2]
        pi += 3
        self.cubic_to(cp1.x, cp1.y, cp2.x, cp2.y, end.x, end.y)
      }
      Close => self.close()
    }
  }
}

///|
/// 別の Path を平行移動して追加する。
pub fn Path::add_path_translated(
  self : Path,
  other : Path,
  dx : Double,
  dy : Double,
) -> Unit raise RadenError {
  let mut pi = 0
  let mut wi = 0
  for cmd in other.cmds {
    match cmd {
      MoveTo => {
        let p = other.points[pi]
        pi += 1
        self.move_to(p.x + dx, p.y + dy)
      }
      LineTo => {
        let p = other.points[pi]
        pi += 1
        self.line_to(p.x + dx, p.y + dy)
      }
      QuadTo => {
        let cp = other.points[pi]
        let end = other.points[pi + 1]
        pi += 2
        self.quad_to(cp.x + dx, cp.y + dy, end.x + dx, end.y + dy)
      }
      ConicTo => {
        let cp = other.points[pi]
        let end = other.points[pi + 1]
        pi += 2
        let w = other.conic_weights[wi]
        wi += 1
        self.conic_to(cp.x + dx, cp.y + dy, end.x + dx, end.y + dy, w)
      }
      CubicTo => {
        let cp1 = other.points[pi]
        let cp2 = other.points[pi + 1]
        let end = other.points[pi + 2]
        pi += 3
        self.cubic_to(
          cp1.x + dx,
          cp1.y + dy,
          cp2.x + dx,
          cp2.y + dy,
          end.x + dx,
          end.y + dy,
        )
      }
      Close => self.close()
    }
  }
}

///|
/// 別の Path に行列を適用して追加する。
pub fn Path::add_path_transformed(
  self : Path,
  other : Path,
  m : Matrix2D,
) -> Unit raise RadenError {
  let mut pi = 0
  let mut wi = 0
  for cmd in other.cmds {
    match cmd {
      MoveTo => {
        let p = other.points[pi]
        pi += 1
        let (x, y) = m.map_point(p.x, p.y)
        self.move_to(x, y)
      }
      LineTo => {
        let p = other.points[pi]
        pi += 1
        let (x, y) = m.map_point(p.x, p.y)
        self.line_to(x, y)
      }
      QuadTo => {
        let (cx, cy) = m.map_point(other.points[pi].x, other.points[pi].y)
        let (ex, ey) = m.map_point(
          other.points[pi + 1].x,
          other.points[pi + 1].y,
        )
        pi += 2
        self.quad_to(cx, cy, ex, ey)
      }
      ConicTo => {
        let (cx, cy) = m.map_point(other.points[pi].x, other.points[pi].y)
        let (ex, ey) = m.map_point(
          other.points[pi + 1].x,
          other.points[pi + 1].y,
        )
        pi += 2
        let w = other.conic_weights[wi]
        wi += 1
        self.conic_to(cx, cy, ex, ey, w)
      }
      CubicTo => {
        let (c1x, c1y) = m.map_point(other.points[pi].x, other.points[pi].y)
        let (c2x, c2y) = m.map_point(
          other.points[pi + 1].x,
          other.points[pi + 1].y,
        )
        let (ex, ey) = m.map_point(
          other.points[pi + 2].x,
          other.points[pi + 2].y,
        )
        pi += 3
        self.cubic_to(c1x, c1y, c2x, c2y, ex, ey)
      }
      Close => self.close()
    }
  }
}

///|
/// すべての頂点を含む軸並行バウンディングボックスを返す。空パスは `None`。
///
/// 注意: これは制御点を含む `control_box` に相当する (Blend2D の `get_control_box`)。
/// 厳密な曲線のバウンディングボックスではないため、ベジェ制御点が外側に出る場合は
/// 実際のラスタライズ範囲よりも広めの矩形が返る。
pub fn Path::control_box(self : Path) -> Rect? {
  if self.points.is_empty() {
    return None
  }
  let mut min_x = @double.infinity
  let mut min_y = @double.infinity
  let mut max_x = @double.neg_infinity
  let mut max_y = @double.neg_infinity
  for p in self.points {
    if p.x < min_x {
      min_x = p.x
    }
    if p.y < min_y {
      min_y = p.y
    }
    if p.x > max_x {
      max_x = p.x
    }
    if p.y > max_y {
      max_y = p.y
    }
  }
  Some({ x: min_x, y: min_y, w: max_x - min_x, h: max_y - min_y, })
}

///|
/// `control_box` のエイリアス
/// (Blend2D の `get_bounding_box` 相当だが、現状は制御点ベース)。
pub fn Path::bounding_box(self : Path) -> Rect? {
  self.control_box()
}

///|
/// 三角形をパスに追加する (3 頂点を結んで閉じる)。
pub fn Path::add_triangle(
  self : Path,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Unit {
  self.move_to(x0, y0)
  self.line_to(x1, y1)
  self.line_to(x2, y2)
  self.close()
}

///|
/// 点列を結んで閉じたポリゴンを追加する。点が 2 つ以下の場合は何もしない。
pub fn Path::add_polygon(self : Path, points : ArrayView[Point]) -> Unit {
  if points.length() < 3 {
    return
  }
  self.move_to(points[0].x, points[0].y)
  for i in 1..<points.length() {
    self.line_to(points[i].x, points[i].y)
  }
  self.close()
}

///|
/// 点列を結んだ折れ線 (polyline) を追加する。閉じない。
pub fn Path::add_polyline(self : Path, points : ArrayView[Point]) -> Unit {
  if points.length() < 2 {
    return
  }
  self.move_to(points[0].x, points[0].y)
  for i in 1..<points.length() {
    self.line_to(points[i].x, points[i].y)
  }
}

///|
/// 角丸矩形をパスに追加する。
///
/// 角の半径 `rx` / `ry` は幅・高さの半分でクランプされる (Blend2D と同様)。
/// 半径が 0 以下の場合は通常の矩形 (4 本の line_to + close) を追加する。
pub fn Path::add_round_rect(
  self : Path,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  rx : Double,
  ry : Double,
) -> Unit {
  if w <= 0.0 || h <= 0.0 {
    return
  }
  let rx = @cmp.maximum(rx, 0.0).min(w * 0.5)
  let ry = @cmp.maximum(ry, 0.0).min(h * 0.5)
  if rx == 0.0 || ry == 0.0 {
    self.move_to(x, y)
    self.line_to(x + w, y)
    self.line_to(x + w, y + h)
    self.line_to(x, y + h)
    self.close()
    return
  }
  let kx = rx * kappa
  let ky = ry * kappa
  let x1 = x + w
  let y1 = y + h

  // 上辺 (左上の弧の終点 → 右上の弧の始点)
  self.move_to(x + rx, y)
  self.line_to(x1 - rx, y)
  // 右上の角
  self.cubic_to(x1 - rx + kx, y, x1, y + ry - ky, x1, y + ry)
  // 右辺
  self.line_to(x1, y1 - ry)
  // 右下の角
  self.cubic_to(x1, y1 - ry + ky, x1 - rx + kx, y1, x1 - rx, y1)
  // 下辺
  self.line_to(x + rx, y1)
  // 左下の角
  self.cubic_to(x + rx - kx, y1, x, y1 - ry + ky, x, y1 - ry)
  // 左辺
  self.line_to(x, y + ry)
  // 左上の角
  self.cubic_to(x, y + ry - ky, x + rx - kx, y, x + rx, y)
  self.close()
}

///|
/// 楕円を 4 本の cubic Bezier で近似して追加する。
/// `add_circle` の `rx == ry` 版と一致する。
pub fn Path::add_ellipse(
  self : Path,
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
) -> Unit {
  let kx = rx * kappa
  let ky = ry * kappa
  self.move_to(cx + rx, cy)
  self.cubic_to(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
  self.cubic_to(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
  self.cubic_to(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
  self.cubic_to(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
  self.close()
}

///|
/// 円を 4 本の cubic Bezier で近似して追加する。Blend2D と同一のアルゴリズム。
pub fn Path::add_circle(
  self : Path,
  cx : Double,
  cy : Double,
  r : Double,
) -> Unit {
  let kx = r * kappa
  let ky = r * kappa

  // 右端 (cx+r, cy) から反時計回り
  self.move_to(cx + r, cy)

  // 右端 → 下端
  self.cubic_to(cx + r, cy + ky, cx + kx, cy + r, cx, cy + r)

  // 下端 → 左端
  self.cubic_to(cx - kx, cy + r, cx - r, cy + ky, cx - r, cy)

  // 左端 → 上端
  self.cubic_to(cx - r, cy - ky, cx - kx, cy - r, cx, cy - r)

  // 上端 → 右端
  self.cubic_to(cx + kx, cy - r, cx + r, cy - ky, cx + r, cy)

  self.close()
}

///|
/// 円弧を cubic Bézier セグメントで近似して Path に追加する。
///
/// sweep を π/2 以下のセグメントに分割し、各セグメントを 1 本の cubic Bézier で近似する。
/// 制御点の算出は標準的な端点パラメータ化に基づく。
fn add_arc_segments(
  path : Path,
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
  start : Double,
  sweep : Double,
) -> Unit {
  let half_pi = @math.PI / 2.0
  let abs_sweep = sweep.abs()
  // π/2 以下に分割するセグメント数
  let n = @cmp.maximum((abs_sweep / half_pi).ceil().to_int(), 1)
  let segment_sweep = sweep / n.to_double()

  let mut angle = start
  for i in 0..<n {
    let _ = i
    add_arc_cubic(path, cx, cy, rx, ry, angle, segment_sweep)
    angle += segment_sweep
  }
}

///|
/// 1 セグメント (|sweep| ≤ π/2) の円弧を 1 本の cubic Bézier で近似する。
fn add_arc_cubic(
  path : Path,
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
  start : Double,
  sweep : Double,
) -> Unit {
  // k = (4/3) * tan(sweep/4) — 標準的な円弧近似係数
  let k = 4.0 / 3.0 * @math.tan(sweep / 4.0)

  let (sin0, cos0) = (@math.sin(start), @math.cos(start))
  let end = start + sweep
  let (sin1, cos1) = (@math.sin(end), @math.cos(end))

  // 制御点 1: 開始点の接線方向
  let cp1x = cx + rx * (cos0 - k * sin0)
  let cp1y = cy + ry * (sin0 + k * cos0)

  // 制御点 2: 終点の接線方向 (逆向き)
  let cp2x = cx + rx * (cos1 + k * sin1)
  let cp2y = cy + ry * (sin1 - k * cos1)

  // 終点
  let ex = cx + rx * cos1
  let ey = cy + ry * sin1

  path.cubic_to(cp1x, cp1y, cp2x, cp2y, ex, ey)
}

///|
pub extend PathCmd with Eq::{not_equal, equal}

///|
pub extend PathCmd with @debug.Debug::{to_repr}
