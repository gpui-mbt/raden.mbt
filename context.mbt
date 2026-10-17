///|
/// 描画コンテキスト。上流 `api/context.rs` の `Context` に対応。
///
/// 上流は Cranelift JIT でパイプラインを生成するが、
/// 移植版は同じ観測結果をスカラ合成で再現する。
/// JIT に相当する `PipelineRuntime` は workspace 境界として残す。

///|
/// 上流 `PipelineRuntime` (JIT キャッシュ) の代替。
/// 移植版は JIT を持たずスカラ合成で処理するため、
/// 現時点では状態を持たない。フレームをまたぐ workspace 用の境界として残す。
pub struct PipelineRuntime {
  priv unit : Int32
}

///|
pub fn PipelineRuntime::new() -> PipelineRuntime {
  { unit: 0, }
}

///|
/// `save` / `restore` で保存・復元される描画状態。
/// 上流 `ContextState` に対応 (gradient/pattern は RADEN-0007 で追加)。
priv struct ContextState {
  comp_op : CompOp
  fill_rule : FillRule
  fill_color_prgb32 : UInt32
  fill_gradient : Gradient?
  fill_pattern : Pattern?
  stroke_color_prgb32 : UInt32
  stroke_gradient : Gradient?
  stroke_pattern : Pattern?
  stroke_width : Double
  stroke_start_cap : StrokeCap
  stroke_end_cap : StrokeCap
  stroke_join : StrokeJoin
  stroke_miter_limit : Double
  stroke_dash_array : Array[Double]
  stroke_dash_offset : Double
  matrix : Matrix2D
  global_alpha : Double
  fill_alpha : Double
  stroke_alpha : Double
  /// ユーザー指定のクリップ領域
  clip_box : BoxI
}

///|
/// 描画コンテキスト本体。
///
/// `Image` と `PipelineRuntime` への参照を保持する (上流は借用期付き参照、
/// GC 言語のため所有構造体フィールドとする)。
/// `Context` 自体は `Image` の所有者ではないため、呼び出し側は
/// 描画結果を得るために `Image` の参照を保持する必要がある。
pub struct Context {
  priv image : Image
  priv runtime : PipelineRuntime
  priv mut comp_op : CompOp
  priv mut fill_rule : FillRule
  priv mut fill_color_prgb32 : UInt32
  priv mut fill_gradient : Gradient?
  priv mut fill_pattern : Pattern?
  priv mut stroke_color_prgb32 : UInt32
  priv mut stroke_gradient : Gradient?
  priv mut stroke_pattern : Pattern?
  priv mut stroke_width : Double
  priv mut stroke_start_cap : StrokeCap
  priv mut stroke_end_cap : StrokeCap
  priv mut stroke_join : StrokeJoin
  priv mut stroke_miter_limit : Double
  priv mut stroke_dash_array : Array[Double]
  priv mut stroke_dash_offset : Double
  priv mut matrix : Matrix2D
  priv mut global_alpha : Double
  priv mut fill_alpha : Double
  priv mut stroke_alpha : Double
  /// メタクリップ (画像境界)。restore_clipping で戻る先。
  priv meta_clip_box : BoxI
  /// 現在のクリップ領域。clip_to_rect で縮小される。
  priv mut clip_box : BoxI
  priv state_stack : Array[ContextState]
  priv tmp_path : Path
  priv stroke_path_buf : Path
  priv edge_buf : Array[Edge]
  /// グラデーション/パターンの fill_path スパン用スクラッチバッファ。
  /// 上流 `gradient_span_buf` に対応。
  priv span_buf : Ref[FixedArray[UInt32]]
  priv rasterizer : @raster.AnalyticRasterizer
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
pub fn Context::new(image : Image, runtime : PipelineRuntime) -> Context {
  let meta_clip_box : BoxI = {
    x0: 0,
    y0: 0,
    x1: image.width(),
    y1: image.height(),
  }
  {
    image,
    runtime,
    comp_op: SrcOver,
    fill_rule: NonZero,
    fill_color_prgb32: 0,
    fill_gradient: None,
    fill_pattern: None,
    stroke_color_prgb32: 0,
    stroke_gradient: None,
    stroke_pattern: None,
    stroke_width: 1.0,
    stroke_start_cap: Butt,
    stroke_end_cap: Butt,
    stroke_join: MiterClip,
    stroke_miter_limit: 4.0,
    stroke_dash_array: [],
    stroke_dash_offset: 0.0,
    matrix: Matrix2D::identity(),
    global_alpha: 1.0,
    fill_alpha: 1.0,
    stroke_alpha: 1.0,
    meta_clip_box,
    clip_box: {
      x0: meta_clip_box.x0,
      y0: meta_clip_box.y0,
      x1: meta_clip_box.x1,
      y1: meta_clip_box.y1,
    },
    state_stack: [],
    tmp_path: Path::new(),
    stroke_path_buf: Path::new(),
    edge_buf: [],
    span_buf: Ref(FixedArray::make(0, 0)),
    rasterizer: @raster.AnalyticRasterizer::new(),
  }
}

///|
/// 現在の描画状態をスタックに保存する。
/// 行列・クリップ・ダッシュ配列は値として保存し、
/// 後続の変更が保存済み状態を汚さないようにする。
pub fn Context::save(self : Context) -> Unit {
  self.state_stack.push({
    comp_op: self.comp_op,
    fill_rule: self.fill_rule,
    fill_color_prgb32: self.fill_color_prgb32,
    fill_gradient: self.fill_gradient,
    fill_pattern: self.fill_pattern,
    stroke_color_prgb32: self.stroke_color_prgb32,
    stroke_gradient: self.stroke_gradient,
    stroke_pattern: self.stroke_pattern,
    stroke_width: self.stroke_width,
    stroke_start_cap: self.stroke_start_cap,
    stroke_end_cap: self.stroke_end_cap,
    stroke_join: self.stroke_join,
    stroke_miter_limit: self.stroke_miter_limit,
    stroke_dash_array: self.stroke_dash_array.copy(),
    stroke_dash_offset: self.stroke_dash_offset,
    matrix: {
      m00: self.matrix.m00,
      m01: self.matrix.m01,
      m10: self.matrix.m10,
      m11: self.matrix.m11,
      m20: self.matrix.m20,
      m21: self.matrix.m21,
    },
    global_alpha: self.global_alpha,
    fill_alpha: self.fill_alpha,
    stroke_alpha: self.stroke_alpha,
    clip_box: {
      x0: self.clip_box.x0,
      y0: self.clip_box.y0,
      x1: self.clip_box.x1,
      y1: self.clip_box.y1,
    },
  })
}

///|
/// スタックから描画状態を復元する。スタックが空の場合は何もしない。
pub fn Context::restore(self : Context) -> Unit {
  match self.state_stack.pop() {
    None => ()
    Some(state) => {
      self.comp_op = state.comp_op
      self.fill_rule = state.fill_rule
      self.fill_color_prgb32 = state.fill_color_prgb32
      self.fill_gradient = state.fill_gradient
      self.fill_pattern = state.fill_pattern
      self.stroke_color_prgb32 = state.stroke_color_prgb32
      self.stroke_gradient = state.stroke_gradient
      self.stroke_pattern = state.stroke_pattern
      self.stroke_width = state.stroke_width
      self.stroke_start_cap = state.stroke_start_cap
      self.stroke_end_cap = state.stroke_end_cap
      self.stroke_join = state.stroke_join
      self.stroke_miter_limit = state.stroke_miter_limit
      self.stroke_dash_array = state.stroke_dash_array
      self.stroke_dash_offset = state.stroke_dash_offset
      self.matrix = state.matrix
      self.global_alpha = state.global_alpha
      self.fill_alpha = state.fill_alpha
      self.stroke_alpha = state.stroke_alpha
      self.clip_box = state.clip_box
    }
  }
}

///|
pub fn Context::set_comp_op(self : Context, op : CompOp) -> Unit {
  self.comp_op = op
}

///|
pub fn Context::comp_op(self : Context) -> CompOp {
  self.comp_op
}

///|
/// 塗りつぶし規則を設定する。
pub fn Context::set_fill_rule(self : Context, rule : FillRule) -> Unit {
  self.fill_rule = rule
}

///|
pub fn Context::fill_rule(self : Context) -> FillRule {
  self.fill_rule
}

///|
/// 単色塗りつぶしの premultiplied ARGB32 (`set_fill_style` が設定した値)。
pub fn Context::fill_color_prgb32(self : Context) -> UInt32 {
  self.fill_color_prgb32
}

///|
/// 塗りつぶしグラデーション (未設定なら None)。
pub fn Context::fill_gradient(self : Context) -> Gradient? {
  self.fill_gradient
}

///|
/// 塗りつぶしパターン (未設定なら None)。
pub fn Context::fill_pattern(self : Context) -> Pattern? {
  self.fill_pattern
}

///|
/// 単色ストロークの premultiplied ARGB32。
pub fn Context::stroke_color_prgb32(self : Context) -> UInt32 {
  self.stroke_color_prgb32
}

///|
/// ストロークグラデーション (未設定なら None)。
pub fn Context::stroke_gradient(self : Context) -> Gradient? {
  self.stroke_gradient
}

///|
/// ストロークパターン (未設定なら None)。
pub fn Context::stroke_pattern(self : Context) -> Pattern? {
  self.stroke_pattern
}

///|
pub fn Context::stroke_width(self : Context) -> Double {
  self.stroke_width
}

///|
pub fn Context::stroke_miter_limit(self : Context) -> Double {
  self.stroke_miter_limit
}

///|
pub fn Context::stroke_join(self : Context) -> StrokeJoin {
  self.stroke_join
}

///|
pub fn Context::stroke_start_cap(self : Context) -> StrokeCap {
  self.stroke_start_cap
}

///|
pub fn Context::stroke_end_cap(self : Context) -> StrokeCap {
  self.stroke_end_cap
}

///|
pub fn Context::stroke_dash_array(self : Context) -> ArrayView[Double] {
  self.stroke_dash_array[:]
}

///|
pub fn Context::stroke_dash_offset(self : Context) -> Double {
  self.stroke_dash_offset
}

///|
/// 現在の変換行列のコピーを返す。
/// 上流は `&Matrix2D` を返すが、移植版ではスナップショットを返し
/// 呼び出し側の変更がコンテキスト状態を汚さないようにする。
pub fn Context::matrix(self : Context) -> Matrix2D {
  {
    m00: self.matrix.m00,
    m01: self.matrix.m01,
    m10: self.matrix.m10,
    m11: self.matrix.m11,
    m20: self.matrix.m20,
    m21: self.matrix.m21,
  }
}

///|
pub fn Context::global_alpha(self : Context) -> Double {
  self.global_alpha
}

///|
/// 全描画に乗算されるグローバルアルファを設定する。値域 [0, 1] でクランプする。
pub fn Context::set_global_alpha(self : Context, a : Double) -> Unit {
  self.global_alpha = if a < 0.0 { 0.0 } else if a > 1.0 { 1.0 } else { a }
}

///|
pub fn Context::fill_alpha(self : Context) -> Double {
  self.fill_alpha
}

///|
/// fill 個別のアルファを設定する。値域 [0, 1] でクランプする。
pub fn Context::set_fill_alpha(self : Context, a : Double) -> Unit {
  self.fill_alpha = if a < 0.0 { 0.0 } else if a > 1.0 { 1.0 } else { a }
}

///|
pub fn Context::stroke_alpha(self : Context) -> Double {
  self.stroke_alpha
}

///|
/// stroke 個別のアルファを設定する。値域 [0, 1] でクランプする。
pub fn Context::set_stroke_alpha(self : Context, a : Double) -> Unit {
  self.stroke_alpha = if a < 0.0 { 0.0 } else if a > 1.0 { 1.0 } else { a }
}

///|
/// fill 経路で適用される実効アルファ (global * fill) を 0..=255 で返す。
fn Context::effective_fill_alpha_u8(self : Context) -> UInt32 {
  @pixel.alpha_to_u8(self.global_alpha * self.fill_alpha)
}

///|
/// fill 経路で適用される実効アルファ (global * stroke) を 0..=255 で返す。
fn Context::effective_stroke_alpha_u8(self : Context) -> UInt32 {
  @pixel.alpha_to_u8(self.global_alpha * self.stroke_alpha)
}

///|
/// 単色塗りつぶしスタイルを設定する。グラデーション/パターンは解除される。
pub fn Context::set_fill_style(self : Context, color : Rgba32) -> Unit {
  self.fill_color_prgb32 = color.to_prgb32()
  self.fill_gradient = None
  self.fill_pattern = None
}

///|
/// 塗りつぶしスタイルをグラデーションに設定する。
/// 上流同様、設定時点の内容をスナップショットとして保持する。
pub fn Context::set_fill_style_gradient(
  self : Context,
  gradient : Gradient,
) -> Unit {
  self.fill_gradient = Some(gradient.copy())
  self.fill_pattern = None
}

///|
/// 塗りつぶしスタイルをパターンに設定する。
/// 上流同様、設定時点の内容をスナップショットとして保持する。
pub fn Context::set_fill_style_pattern(
  self : Context,
  pattern : Pattern,
) -> Unit {
  self.fill_pattern = Some(pattern.copy())
  self.fill_gradient = None
}

///|
/// ストローク色を設定する。グラデーション/パターンは解除される。
pub fn Context::set_stroke_style(self : Context, color : Rgba32) -> Unit {
  self.stroke_color_prgb32 = color.to_prgb32()
  self.stroke_gradient = None
  self.stroke_pattern = None
}

///|
/// ストロークスタイルをグラデーションに設定する。
pub fn Context::set_stroke_style_gradient(
  self : Context,
  gradient : Gradient,
) -> Unit {
  self.stroke_gradient = Some(gradient.copy())
  self.stroke_pattern = None
}

///|
/// ストロークスタイルをパターンに設定する。
pub fn Context::set_stroke_style_pattern(
  self : Context,
  pattern : Pattern,
) -> Unit {
  self.stroke_pattern = Some(pattern.copy())
  self.stroke_gradient = None
}

///|
/// 平行移動を現在の変換行列に後乗算で適用する。
pub fn Context::translate(self : Context, tx : Double, ty : Double) -> Unit {
  self.matrix.translate(tx, ty)
}

///|
/// スケーリングを現在の変換行列に後乗算で適用する。
pub fn Context::scale(self : Context, sx : Double, sy : Double) -> Unit {
  self.matrix.scale(sx, sy)
}

///|
/// 回転を現在の変換行列に後乗算で適用する。角度はラジアン。
pub fn Context::rotate(self : Context, angle : Double) -> Unit {
  self.matrix.rotate(angle)
}

///|
/// 任意の行列を現在の変換行列に後乗算で適用する。
pub fn Context::apply_matrix(self : Context, m : Matrix2D) -> Unit {
  self.matrix = self.matrix.multiply(m)
}

///|
/// 変換行列を単位行列にリセットする。
pub fn Context::reset_matrix(self : Context) -> Unit {
  self.matrix.reset()
}

///|
/// 指定中心まわりの回転を現在の変換行列に後乗算で適用する。角度はラジアン。
pub fn Context::rotate_around(
  self : Context,
  angle : Double,
  cx : Double,
  cy : Double,
) -> Unit {
  self.matrix.rotate_around(angle, cx, cy)
}

///|
/// せん断を現在の変換行列に後乗算で適用する。
/// 係数は Blend2D の `skew` と同様 (接線)。
pub fn Context::skew(self : Context, kx : Double, ky : Double) -> Unit {
  self.matrix.skew(kx, ky)
}

///|
/// 平行移動を現在の変換行列に前乗算で適用する (`post_translate`)。
pub fn Context::post_translate(
  self : Context,
  tx : Double,
  ty : Double,
) -> Unit {
  self.matrix.post_translate(tx, ty)
}

///|
/// スケーリングを現在の変換行列に前乗算で適用する (`post_scale`)。
pub fn Context::post_scale(self : Context, sx : Double, sy : Double) -> Unit {
  self.matrix.post_scale(sx, sy)
}

///|
/// 回転を現在の変換行列に前乗算で適用する (`post_rotate`)。角度はラジアン。
pub fn Context::post_rotate(self : Context, angle : Double) -> Unit {
  self.matrix.post_rotate(angle)
}

///|
/// せん断を現在の変換行列に前乗算で適用する (`post_skew`)。
pub fn Context::post_skew(self : Context, kx : Double, ky : Double) -> Unit {
  self.matrix.post_skew(kx, ky)
}

///|
/// 任意の行列を現在の変換行列に前乗算で適用する (`post_transform`)。
pub fn Context::post_transform(self : Context, m : Matrix2D) -> Unit {
  self.matrix.post_transform(m)
}

///|
/// クリップ領域を指定矩形との積集合に縮小する。
///
/// 複数回呼び出すとクリップ領域は縮小のみされる (拡大はできない)。
/// `save` / `restore` でクリップ状態も保存・復元される。
pub fn Context::clip_to_rect(self : Context, rect : Rect) -> Unit {
  let x0 = f64_to_i32_sat(rect.x.floor())
  let y0 = f64_to_i32_sat(rect.y.floor())
  let x1 = f64_to_i32_sat((rect.x + rect.w).ceil())
  let y1 = f64_to_i32_sat((rect.y + rect.h).ceil())

  self.clip_box.x0 = @cmp.maximum(self.clip_box.x0, x0)
  self.clip_box.y0 = @cmp.maximum(self.clip_box.y0, y0)
  self.clip_box.x1 = @cmp.minimum(self.clip_box.x1, x1)
  self.clip_box.y1 = @cmp.minimum(self.clip_box.y1, y1)
}

///|
/// クリップ領域をメタクリップ (画像境界) にリセットする。
pub fn Context::restore_clipping(self : Context) -> Unit {
  self.clip_box = {
    x0: self.meta_clip_box.x0,
    y0: self.meta_clip_box.y0,
    x1: self.meta_clip_box.x1,
    y1: self.meta_clip_box.y1,
  }
}

///|
/// Blend2D の `userToMeta()` に相当する呼び出し口。
///
/// Blend2D ではユーザ空間行列をメタ空間へ確定したうえでユーザ行列を単位に戻す。
/// raden はメタ行列を別保持していないため、現状はユーザ相当の行列のみを単位にリセットする。
pub fn Context::user_to_meta(self : Context) -> Unit {
  self.matrix.reset()
}

///|
/// 現在のクリップ領域全体をピクセル値 0 でクリアする。
///
/// `set_comp_op(Clear)` + `fill_all` と等価だが、
/// 合成モードやストロークスタイルを汚さずに実行する。
pub fn Context::clear_all(self : Context) -> Unit {
  let w = self.image.width().to_double()
  let h = self.image.height().to_double()
  self.clear_rect(Rect::new(0.0, 0.0, w, h))
}

///|
/// 指定矩形をピクセル値 0 でクリアする。
///
/// 現在のクリップ領域との積集合のみを書き換える。変換行列は無視する
/// (Blend2D の `clear_rect` も同様にデバイス座標で動作する)。
pub fn Context::clear_rect(self : Context, rect : Rect) -> Unit {
  guard self.clip_rect(rect) is Some(boxi) else { return }
  let bpp = self.image.format().bytes_per_pixel()
  let stride = self.image.stride()
  let row_bytes = (boxi.x1 - boxi.x0) * bpp
  for y in boxi.y0..<boxi.y1 {
    let offset = y * stride + boxi.x0 * bpp
    for i in 0..<row_bytes {
      self.image.data[offset + i] = b'\x00'
    }
  }
}

///|
/// 矩形を現在の塗りつぶしスタイルで塗りつぶす。
/// 上流 `fill_rect` を移植したもの。グラデーション/パターンは
/// ラスタライザを経由せず矩形への直接描画を行う。
pub fn Context::fill_rect(self : Context, rect : Rect) -> Unit raise RadenError {
  let eff_alpha = self.effective_fill_alpha_u8()

  // 実効アルファが 1.0 未満でグラデ/パターンの場合は span path 経由
  // (fill_path) を使う。fill_rect の高速パスは alpha 適用に対応しないため。
  if eff_alpha != 0xFF &&
    (self.fill_gradient is Some(_) || self.fill_pattern is Some(_)) {
    let path = self.tmp_path
    path.clear()
    path.move_to(rect.x, rect.y)
    path.line_to(rect.x + rect.w, rect.y)
    path.line_to(rect.x + rect.w, rect.y + rect.h)
    path.line_to(rect.x, rect.y + rect.h)
    path.close()
    self.fill_path(path)
    return
  }

  // 変換行列が identity でない場合、矩形をパスに変換して fill_path にフォールバック
  if !self.matrix.is_identity() {
    let path = self.tmp_path
    path.clear()
    path.move_to(rect.x, rect.y)
    path.line_to(rect.x + rect.w, rect.y)
    path.line_to(rect.x + rect.w, rect.y + rect.h)
    path.line_to(rect.x, rect.y + rect.h)
    path.close()
    self.fill_path(path)
    return
  }

  // A8 宛先にパターン/グラデーションは非対応 (上流は panic)
  if self.image.format() == A8 &&
    (self.fill_pattern is Some(_) || self.fill_gradient is Some(_)) {
    raise UnsupportedFeature(
      "pattern and gradient fills are not supported for A8 destination",
    )
  }

  // パターンの場合はラスタライザを経由せず直接描画する。
  // comp_op は SrcCopy/SrcOver のみ対応 (上流同様、それ以外は panic 相当)。
  if self.fill_pattern is Some(pattern) {
    guard self.clip_rect(rect) is Some(boxi) else { return }
    let prepared = pattern.prepare(self.matrix)
    prepared.fill_rect(
      self.image,
      self.comp_op,
      boxi.x0,
      boxi.y0,
      boxi.x1 - boxi.x0,
      boxi.y1 - boxi.y0,
    )
    return
  }

  // グラデーションの場合もラスタライザを経由せず直接描画する。
  // 上流同様 comp_op は参照しない (不透明 LUT → 直接ストア、半透明 → SrcOver)。
  if self.fill_gradient is Some(gradient) {
    guard self.clip_rect(rect) is Some(boxi) else { return }
    let prepared = gradient.prepare(self.matrix)
    prepared.fill_rect(
      self.image,
      boxi.x0,
      boxi.y0,
      boxi.x1 - boxi.x0,
      boxi.y1 - boxi.y0,
    )
    return
  }

  let prgb32 = @pixel.scale_prgb32(self.fill_color_prgb32, eff_alpha)
  let alpha = (prgb32 >> 24) & 0xFF

  // alpha ファストパス: SrcOver で完全透明なら描画不要
  if self.comp_op == SrcOver && alpha == 0 {
    return
  }

  guard self.clip_rect(rect) is Some(boxi) else { return }

  // alpha ファストパス: SrcOver で完全不透明なら SrcCopy と等価
  let effective_op = if self.comp_op == SrcOver && alpha == 255 {
    SrcCopy
  } else {
    self.comp_op
  }

  self.fill_box_solid(boxi, prgb32, effective_op)
}

///|
/// クリップ済み整数矩形への単色ボックス描画。
/// 上流の Box パイプライン (fill_rect の JIT ループ) に対応するスカラ版。
/// 描画前に合成関数を解決し、未対応の op は部分書き込みせずエラーにする。
fn Context::fill_box_solid(
  self : Context,
  boxi : BoxI,
  prgb32 : UInt32,
  op : CompOp,
) -> Unit raise RadenError {
  let stride = self.image.stride()
  match self.image.format() {
    A8 => {
      // A8 は 4 種類の op のみ対応 (上流も panic で制限)
      let a8op : (UInt32, UInt32) -> UInt32 = match op {
        SrcOver => @pixel.a8_src_over
        SrcCopy => @pixel.a8_src_copy
        Clear => @pixel.a8_clear
        Plus => @pixel.a8_plus
        _ =>
          raise UnsupportedFeature(
            "comp_op \{op} is not supported for A8 destination",
          )
      }
      for y in boxi.y0..<boxi.y1 {
        let row = y * stride
        for x in boxi.x0..<boxi.x1 {
          let off = row + x
          let d = self.image.data[off].to_uint()
          self.image.data[off] = a8op(d, prgb32).to_byte()
        }
      }
    }
    _ => {
      // Prgb32 / Xrgb32 は同じパイプラインを共有する (上流 jit_dst_format)
      // 上流 JIT は行ごとに `width - width % 4` ピクセルを SIMD 経路、
      // 末尾 `width % 4` ピクセルをスカラ経路で処理する (blend_modes.rs
      // の ColorDodge/ColorBurn は両経路で結果が異なるため区別が必要)。
      let (comp_simd, comp_scalar) = select_comp_fns(op)
      let width = boxi.x1 - boxi.x0
      let simd_end = boxi.x1 - width % 4
      for y in boxi.y0..<boxi.y1 {
        let row = y * stride
        for x in boxi.x0..<boxi.x1 {
          let off = row + x * 4
          let dst = self.image.read_u32(off)
          let comp = if x < simd_end { comp_simd } else { comp_scalar }
          self.image.write_u32(off, comp(dst, prgb32))
        }
      }
    }
  }
}

///|
/// パスを現在の塗りつぶし色で塗りつぶす。
/// 上流 `fill_path` の単色パスを移植したもの。
/// A8 宛先は上流も panic のため `UnsupportedFeature` とする。
pub fn Context::fill_path(self : Context, path : Path) -> Unit raise RadenError {
  if self.image.format() == A8 {
    raise UnsupportedFeature("fill_path is not supported for A8 destination")
  }
  let eff_alpha = self.effective_fill_alpha_u8()

  // 実効アルファが 0 の場合は SrcOver のみ早期 return
  // (Clear などはゼロを書く必要があるため一律では省略しない)。
  if self.comp_op == SrcOver && eff_alpha == 0 {
    return
  }

  // グラデーション/パターンの場合は色アルファのチェックをスキップする
  // (上流同様: スタイル側のアルファが描画色を決める)。
  if self.fill_gradient is None && self.fill_pattern is None {
    // alpha ファストパス: SrcOver で完全透明なら描画不要
    if self.comp_op == SrcOver && self.fill_color_prgb32 >> 24 == 0 {
      return
    }
  }

  // バウンディングボックスを計算
  let points = path.points()
  if points.is_empty() {
    return
  }

  let has_transform = !self.matrix.is_identity()

  let mut min_x = @double.infinity
  let mut min_y = @double.infinity
  let mut max_x = @double.neg_infinity
  let mut max_y = @double.neg_infinity

  if has_transform {
    // 変換がある場合: 原座標の bbox の 4 頂点を変換し、AABB を算出
    let mut raw_min_x = @double.infinity
    let mut raw_min_y = @double.infinity
    let mut raw_max_x = @double.neg_infinity
    let mut raw_max_y = @double.neg_infinity
    for p in points {
      raw_min_x = @cmp.minimum(raw_min_x, p.x)
      raw_min_y = @cmp.minimum(raw_min_y, p.y)
      raw_max_x = @cmp.maximum(raw_max_x, p.x)
      raw_max_y = @cmp.maximum(raw_max_y, p.y)
    }
    // bbox の 4 頂点を変換
    let corners = [
      self.matrix.map_point(raw_min_x, raw_min_y),
      self.matrix.map_point(raw_max_x, raw_min_y),
      self.matrix.map_point(raw_max_x, raw_max_y),
      self.matrix.map_point(raw_min_x, raw_max_y),
    ]
    for c in corners {
      min_x = @cmp.minimum(min_x, c.0)
      min_y = @cmp.minimum(min_y, c.1)
      max_x = @cmp.maximum(max_x, c.0)
      max_y = @cmp.maximum(max_y, c.1)
    }
  } else {
    for p in points {
      min_x = @cmp.minimum(min_x, p.x)
      min_y = @cmp.minimum(min_y, p.y)
      max_x = @cmp.maximum(max_x, p.x)
      max_y = @cmp.maximum(max_y, p.y)
    }
  }

  // クリップ領域でクリップ
  let clip_x0 = @cmp.maximum(f64_to_i32_sat(min_x.floor()), self.clip_box.x0)
  let clip_y0 = @cmp.maximum(f64_to_i32_sat(min_y.floor()), self.clip_box.y0)
  let clip_x1 = @cmp.minimum(f64_to_i32_sat(max_x.ceil()) + 1, self.clip_box.x1)
  let clip_y1 = @cmp.minimum(f64_to_i32_sat(max_y.ceil()) + 1, self.clip_box.y1)

  if clip_x0 >= clip_x1 || clip_y0 >= clip_y1 {
    return
  }

  // 合成関数を先に解決する (部分書き込みを避けるためラスタライズ前に判定)。
  // SrcCopy/Clear/DstCopy は coverage で特別扱いされる (上流 build_*_cov と同じ):
  // SrcCopy は dst を読まず scaled src を書く、Clear は dst を (256-cov) で減衰、
  // DstCopy は何も書かない (no-op)。それ以外は汎用の「cov 適用 src → compose」。
  // ランの先頭 `count - count % 4` ピクセルは SIMD 経路、末尾はスカラ経路
  // (上流 core_pipelines の simd_count/remainder 分割に対応)。
  let comp_cov_pair : (
    (UInt32, UInt32, UInt32) -> UInt32,
    (UInt32, UInt32, UInt32) -> UInt32,
  ) = match self.comp_op {
    SrcOver => (@pixel.comp_src_over_cov, @pixel.comp_src_over_cov)
    SrcCopy => (@pixel.comp_src_copy_cov, @pixel.comp_src_copy_cov)
    Clear => (@pixel.comp_clear_cov, @pixel.comp_clear_cov)
    DstCopy =>
      (
        fn(dst : UInt32, src : UInt32, cov : UInt32) -> UInt32 {
          let _ = src
          let _ = cov
          dst
        },
        fn(dst : UInt32, src : UInt32, cov : UInt32) -> UInt32 {
          let _ = src
          let _ = cov
          dst
        },
      )
    op => {
      let (fs, ft) = select_comp_fns(op)
      (
        fn(d : UInt32, s : UInt32, c : UInt32) -> UInt32 {
          @pixel.comp_generic_cov(fs, d, s, c)
        },
        fn(d : UInt32, s : UInt32, c : UInt32) -> UInt32 {
          @pixel.comp_generic_cov(ft, d, s, c)
        },
      )
    }
  }
  // Path を平坦化して線分を収集
  let edges = self.edge_buf
  edges.clear()
  flatten_path(path, edges)

  if edges.is_empty() {
    return
  }

  // 変換がある場合: エッジ座標を一括変換 (上流の transform_edges JIT に相当)
  if has_transform {
    let m = self.matrix
    for i in 0..<edges.length() {
      let e = edges[i]
      let (nx0, ny0) = m.map_point(e.0, e.1)
      let (nx1, ny1) = m.map_point(e.2, e.3)
      edges[i] = (nx0, ny0, nx1, ny1)
    }
  }

  let stride = self.image.stride()
  let image = self.image

  // パターン/グラデーションのスパン合成。
  // 上流 `compile_span_cov` は comp_op を参照せず全 op で SrcOver 相当の
  // パイプラインを返す (`_ => build_src_over_span_cov`) ため、
  // スタイル付き fill_path は常に SrcOver 合成になる (バグ互換の挙動)。
  // 実効アルファは fetch 後のスパンに乗算してから適用する。
  let styled_cov_pair : (
    (UInt32, UInt32, UInt32) -> UInt32,
    (UInt32, UInt32, UInt32) -> UInt32,
  ) = (@pixel.comp_src_over_cov, @pixel.comp_src_over_cov)

  // パターン描画。
  if self.fill_pattern is Some(pattern) {
    let prepared = pattern.prepare(self.matrix)
    self.fill_path_spans(
      edges,
      clip_x0,
      clip_y0,
      clip_x1,
      clip_y1,
      eff_alpha,
      styled_cov_pair,
      fn(x_start, y, span) { prepared.fetch_span(x_start, y, span) },
    )
    return
  }

  // グラデーション描画。
  if self.fill_gradient is Some(gradient) {
    let prepared = gradient.prepare(self.matrix)
    self.fill_path_spans(
      edges,
      clip_x0,
      clip_y0,
      clip_x1,
      clip_y1,
      eff_alpha,
      styled_cov_pair,
      fn(x_start, y, span) { prepared.fetch_span(x_start, y, span) },
    )
    return
  }

  let prgb32 = @pixel.scale_prgb32(self.fill_color_prgb32, eff_alpha)
  let (comp_cov_simd, comp_cov_scalar) = comp_cov_pair
  self.rasterizer.rasterize(
    edges,
    clip_x0,
    clip_y0,
    clip_x1,
    clip_y1,
    even_odd=self.fill_rule == EvenOdd,
    fn(y, x_start, coverage) {
      let base = y * stride + x_start * 4
      let len = coverage.length()
      let simd_len = len - len % 4
      for i in 0..<len {
        let off = base + i * 4
        let dst = image.read_u32(off)
        let comp_cov = if i < simd_len {
          comp_cov_simd
        } else {
          comp_cov_scalar
        }
        image.write_u32(off, comp_cov(dst, prgb32, coverage[i].to_uint()))
      }
    },
  )
}

///|
/// グラデーション/パターン共通の fill_path スパン経路。
/// 上流の `span_buf` ワークフローに対応:
/// fetch → `scale_span_prgb32` (実効アルファ) → span_cov 合成。
/// ランの先頭 `count - count % 4` は simd_fn、末尾は scalar_fn を使う。
fn Context::fill_path_spans(
  self : Context,
  edges : Array[Edge],
  clip_x0 : Int32,
  clip_y0 : Int32,
  clip_x1 : Int32,
  clip_y1 : Int32,
  eff_alpha : UInt32,
  comp_cov_pair : (
    (UInt32, UInt32, UInt32) -> UInt32,
    (UInt32, UInt32, UInt32) -> UInt32,
  ),
  fetch : (Int32, Int32, FixedArray[UInt32]) -> Unit,
) -> Unit {
  let stride = self.image.stride()
  let image = self.image
  let (comp_cov_simd, comp_cov_scalar) = comp_cov_pair
  let span_buf = self.span_buf
  self.rasterizer.rasterize(
    edges,
    clip_x0,
    clip_y0,
    clip_x1,
    clip_y1,
    even_odd=self.fill_rule == EvenOdd,
    fn(y, x_start, coverage) {
      let len = coverage.length()
      // 上流は Vec::resize で再利用するが、ラン長は可変なので
      // ここでは必要長に一致させてから共有バッファを使う。
      if span_buf.val.length() != len {
        span_buf.val = FixedArray::make(len, 0)
      }
      let span = span_buf.val
      fetch(x_start, y, span)
      // scale_span_prgb32: 実効アルファを各ピクセルに乗算する。
      // 上流は alpha==0xFF / 0x00 を早期処理し、それ以外を逐ピクセル乗算する。
      if eff_alpha == 0 {
        span.fill(0)
      } else if eff_alpha != 0xFF {
        for i in 0..<len {
          span[i] = @pixel.scale_prgb32(span[i], eff_alpha)
        }
      }
      let base = y * stride + x_start * 4
      let simd_len = len - len % 4
      for i in 0..<len {
        let off = base + i * 4
        let dst = image.read_u32(off)
        let comp_cov = if i < simd_len {
          comp_cov_simd
        } else {
          comp_cov_scalar
        }
        image.write_u32(off, comp_cov(dst, span[i], coverage[i].to_uint()))
      }
    },
  )
}

///|
/// 画像全体を現在の塗りつぶし色で塗りつぶす。
pub fn Context::fill_all(self : Context) -> Unit raise RadenError {
  let w = self.image.width().to_double()
  let h = self.image.height().to_double()
  self.fill_rect(Rect::new(0.0, 0.0, w, h))
}

///|
/// 扇形 (pie) を塗りつぶす。
///
/// 中心から弧を経由して中心に戻る閉じた領域を塗りつぶす。
pub fn Context::fill_pie(self : Context, arc : Arc) -> Unit raise RadenError {
  if arc.rx <= 0.0 || arc.ry <= 0.0 || arc.sweep == 0.0 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_pie(arc.cx, arc.cy, arc.rx, arc.ry, arc.start, arc.sweep)
  self.fill_path(path)
}

///|
/// 円を塗りつぶす。
pub fn Context::fill_circle(
  self : Context,
  circle : Circle,
) -> Unit raise RadenError {
  if circle.r <= 0.0 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_circle(circle.cx, circle.cy, circle.r)
  self.fill_path(path)
}

///|
/// 三角形を塗りつぶす。
pub fn Context::fill_triangle(
  self : Context,
  t : Triangle,
) -> Unit raise RadenError {
  let path = self.tmp_path
  path.clear()
  path.add_triangle(t.x0, t.y0, t.x1, t.y1, t.x2, t.y2)
  self.fill_path(path)
}

///|
/// ポリゴンを塗りつぶす。点列が 3 点未満なら何もしない。
pub fn Context::fill_polygon(
  self : Context,
  points : ArrayView[Point],
) -> Unit raise RadenError {
  if points.length() < 3 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_polygon(points)
  self.fill_path(path)
}

///|
/// 角丸矩形を塗りつぶす。
pub fn Context::fill_round_rect(
  self : Context,
  rr : RoundRect,
) -> Unit raise RadenError {
  if rr.w <= 0.0 || rr.h <= 0.0 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_round_rect(rr.x, rr.y, rr.w, rr.h, rr.rx, rr.ry)
  self.fill_path(path)
}

///|
/// 楕円を塗りつぶす。
pub fn Context::fill_ellipse(
  self : Context,
  ellipse : Ellipse,
) -> Unit raise RadenError {
  if ellipse.rx <= 0.0 || ellipse.ry <= 0.0 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_ellipse(ellipse.cx, ellipse.cy, ellipse.rx, ellipse.ry)
  self.fill_path(path)
}

///|
/// ストローク幅を設定する。
pub fn Context::set_stroke_width(self : Context, width : Double) -> Unit {
  self.stroke_width = width
}

///|
/// ストロークの端点形状を始点・終点の両方に一括設定する。
pub fn Context::set_stroke_cap(self : Context, cap : StrokeCap) -> Unit {
  self.stroke_start_cap = cap
  self.stroke_end_cap = cap
}

///|
/// ストロークの始点キャップを設定する。
pub fn Context::set_stroke_start_cap(self : Context, cap : StrokeCap) -> Unit {
  self.stroke_start_cap = cap
}

///|
/// ストロークの終点キャップを設定する。
pub fn Context::set_stroke_end_cap(self : Context, cap : StrokeCap) -> Unit {
  self.stroke_end_cap = cap
}

///|
/// ストロークの接続形状を設定する。
pub fn Context::set_stroke_join(self : Context, join : StrokeJoin) -> Unit {
  self.stroke_join = join
}

///|
/// ストロークのマイターリミットを設定する。
pub fn Context::set_stroke_miter_limit(self : Context, limit : Double) -> Unit {
  self.stroke_miter_limit = limit
}

///|
/// ストロークのダッシュパターンを設定する。
///
/// 交互に「描画区間」「空白区間」の長さを指定する。
/// 空の配列を渡すと実線に戻る。
pub fn Context::set_stroke_dash_array(
  self : Context,
  dash_array : ArrayView[Double],
) -> Unit {
  self.stroke_dash_array = dash_array.to_owned()
}

///|
/// ストロークのダッシュオフセットを設定する。
pub fn Context::set_stroke_dash_offset(self : Context, offset : Double) -> Unit {
  self.stroke_dash_offset = offset
}

///|
/// パスをストローク描画する。
///
/// 上流 `stroke_path` に対応: `stroke_to_fill` でストロークを塗りつぶしパスに
/// 変換し、fill スタイルを一時的にストロークスタイルに差し替えて fill_path する。
/// fill_alpha も一時的に stroke_alpha に差し替えて effective_fill_alpha が
/// ストローク経路の実効アルファを返すようにする。
pub fn Context::stroke_path(
  self : Context,
  path : Path,
) -> Unit raise RadenError {
  self.stroke_path_buf.clear()
  stroke_to_fill(
    path,
    self.stroke_width,
    self.stroke_start_cap,
    self.stroke_end_cap,
    self.stroke_join,
    self.stroke_miter_limit,
    self.stroke_dash_array[:],
    self.stroke_dash_offset,
    self.stroke_path_buf,
  )
  let saved_fill_color = self.fill_color_prgb32
  let saved_fill_gradient = self.fill_gradient
  let saved_fill_pattern = self.fill_pattern
  let saved_fill_alpha = self.fill_alpha
  // ストローク側にグラデ/パターンが設定されていれば優先し、
  // なければ単色を使う (上流同様)。
  self.fill_color_prgb32 = self.stroke_color_prgb32
  self.fill_gradient = self.stroke_gradient
  self.fill_pattern = self.stroke_pattern
  self.fill_alpha = self.stroke_alpha
  // fill 状態はエラー有無にかかわらず必ず元に戻す
  defer {
    self.fill_color_prgb32 = saved_fill_color
    self.fill_gradient = saved_fill_gradient
    self.fill_pattern = saved_fill_pattern
    self.fill_alpha = saved_fill_alpha
  }
  self.fill_path(self.stroke_path_buf)
}

///|
/// 矩形をストローク描画する。
pub fn Context::stroke_rect(
  self : Context,
  rect : Rect,
) -> Unit raise RadenError {
  let path = self.tmp_path
  path.clear()
  path.move_to(rect.x, rect.y)
  path.line_to(rect.x + rect.w, rect.y)
  path.line_to(rect.x + rect.w, rect.y + rect.h)
  path.line_to(rect.x, rect.y + rect.h)
  path.close()
  self.stroke_path(path)
}

///|
/// 円をストローク描画する。
pub fn Context::stroke_circle(
  self : Context,
  circle : Circle,
) -> Unit raise RadenError {
  if circle.r <= 0.0 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_circle(circle.cx, circle.cy, circle.r)
  self.stroke_path(path)
}

///|
/// 三角形をストローク描画する。
pub fn Context::stroke_triangle(
  self : Context,
  t : Triangle,
) -> Unit raise RadenError {
  let path = self.tmp_path
  path.clear()
  path.add_triangle(t.x0, t.y0, t.x1, t.y1, t.x2, t.y2)
  self.stroke_path(path)
}

///|
/// ポリゴンをストローク描画する (閉じる)。
pub fn Context::stroke_polygon(
  self : Context,
  points : ArrayView[Point],
) -> Unit raise RadenError {
  if points.length() < 3 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_polygon(points)
  self.stroke_path(path)
}

///|
/// 折れ線 (polyline) をストローク描画する。閉じない。
pub fn Context::stroke_polyline(
  self : Context,
  points : ArrayView[Point],
) -> Unit raise RadenError {
  if points.length() < 2 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_polyline(points)
  self.stroke_path(path)
}

///|
/// 角丸矩形をストローク描画する。
pub fn Context::stroke_round_rect(
  self : Context,
  rr : RoundRect,
) -> Unit raise RadenError {
  if rr.w <= 0.0 || rr.h <= 0.0 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_round_rect(rr.x, rr.y, rr.w, rr.h, rr.rx, rr.ry)
  self.stroke_path(path)
}

///|
/// 楕円をストローク描画する。
pub fn Context::stroke_ellipse(
  self : Context,
  ellipse : Ellipse,
) -> Unit raise RadenError {
  if ellipse.rx <= 0.0 || ellipse.ry <= 0.0 {
    return
  }
  let path = self.tmp_path
  path.clear()
  path.add_ellipse(ellipse.cx, ellipse.cy, ellipse.rx, ellipse.ry)
  self.stroke_path(path)
}

///|
/// 線分をストローク描画する。
pub fn Context::stroke_line(
  self : Context,
  line : Line,
) -> Unit raise RadenError {
  let path = self.tmp_path
  path.clear()
  path.move_to(line.x0, line.y0)
  path.line_to(line.x1, line.y1)
  self.stroke_path(path)
}

///|
/// 描画を終了する。現在は何もしないが、将来のバッファフラッシュ用。
pub fn Context::end(self : Context) -> Unit {
  ()
}

///|
/// Rect(f64) を現在のクリップ領域でクリップした BoxI(i32) に変換する。
/// 完全にクリップ外の場合は None を返す。
fn Context::clip_rect(self : Context, rect : Rect) -> BoxI? {
  let x0 = f64_to_i32_sat(rect.x.floor())
  let y0 = f64_to_i32_sat(rect.y.floor())
  let x1 = f64_to_i32_sat((rect.x + rect.w).ceil())
  let y1 = f64_to_i32_sat((rect.y + rect.h).ceil())

  let x0 = @cmp.maximum(x0, self.clip_box.x0)
  let y0 = @cmp.maximum(y0, self.clip_box.y0)
  let x1 = @cmp.minimum(x1, self.clip_box.x1)
  let y1 = @cmp.minimum(y1, self.clip_box.y1)

  if x0 >= x1 || y0 >= y1 {
    return None
  }

  Some({ x0, y0, x1, y1, })
}

///|
/// CompOp から 4bpp (Prgb32/Xrgb32) 用の合成関数ペアを解決する。
/// 上流 `compiler/mod.rs` の build_* ディスパッチに対応。
/// 返り値は `(simd_fn, scalar_fn)`。上流の JIT は 1 ランの先頭
/// `count - count % 4` ピクセルを SIMD (I32X4) で、末尾 `count % 4` を
/// スカラで処理する。ColorDodge/ColorBurn は SIMD 経路が f32 演算で
/// スカラと結果が異なるため別関数を返す。SoftLight は両経路とも
/// f32 で同じ結果になるため同一関数を返す。
fn select_comp_fns(
  op : CompOp,
) -> ((UInt32, UInt32) -> UInt32, (UInt32, UInt32) -> UInt32) {
  let scalar = select_comp_fn_scalar(op)
  match op {
    ColorDodge => (@pixel.comp_color_dodge_simd, scalar)
    ColorBurn => (@pixel.comp_color_burn_simd, scalar)
    _ => (scalar, scalar)
  }
}

///|
/// CompOp から 4bpp 用のスカラ合成関数 (ラン末尾 `count % 4` ピクセル用) を
/// 解決する。全 29 op が実装済み (A8 宛先は a8_* 系で 4 op のみ、上流同様)。
fn select_comp_fn_scalar(op : CompOp) -> (UInt32, UInt32) -> UInt32 {
  match op {
    SrcOver => @pixel.comp_src_over
    SrcCopy => @pixel.comp_src_copy
    SrcIn => @pixel.comp_src_in
    SrcOut => @pixel.comp_src_out
    SrcAtop => @pixel.comp_src_atop
    DstOver => @pixel.comp_dst_over
    DstCopy => @pixel.comp_dst_copy
    DstIn => @pixel.comp_dst_in
    DstOut => @pixel.comp_dst_out
    DstAtop => @pixel.comp_dst_atop
    Xor => @pixel.comp_xor
    Clear => @pixel.comp_clear
    Plus => @pixel.comp_plus
    Minus => @pixel.comp_minus
    Modulate => @pixel.comp_modulate
    Multiply => @pixel.comp_multiply
    Screen => @pixel.comp_screen
    Overlay => @pixel.comp_overlay
    Darken => @pixel.comp_darken
    Lighten => @pixel.comp_lighten
    ColorDodge => @pixel.comp_color_dodge
    ColorBurn => @pixel.comp_color_burn
    LinearBurn => @pixel.comp_linear_burn
    LinearLight => @pixel.comp_linear_light
    PinLight => @pixel.comp_pin_light
    HardLight => @pixel.comp_hard_light
    SoftLight => @pixel.comp_soft_light
    Difference => @pixel.comp_difference
    Exclusion => @pixel.comp_exclusion
  }
}
