///|
/// gradient.mbt -- グラデーション
///
/// Linear / Radial / Conic の 3 種類のグラデーションを提供する。
/// 上流 `src/api/gradient.rs` の移植。Blend2D の BLGradient API に準拠。
///
/// 上流はピクセル取得 (fetch) を用途別に複数経路持つ:
/// - `fill_rect` (Linear): 16.48 固定小数点の累積
/// - `fill_rect` (Radial 不透明): JIT I32X4 相当の 4 レーン f32 累積
/// - `fill_rect` (Radial 半透明 / Conic): f32 累積
/// - `fill_path` (Linear): 固定小数点 (`fetch_span_linear_fixed`)
/// - `fill_path` (Radial/Conic): f32 累積 (`fetch_span`)
/// 本実装は同じ経路・同じ演算順序をスカラで再現する。

///|
/// 色停止点。
pub(all) struct GradientStop {
  offset : Double
  color : Rgba32
} derive(Eq, Debug)

///|
pub extend GradientStop with Eq::{not_equal, equal}

///|
pub extend GradientStop with @debug.Debug::{to_repr}

///|
/// 範囲外処理モード。Blend2D の BLExtendMode (シンプルモード) に対応。
pub(all) enum ExtendMode {
  /// 端の色で埋める (デフォルト)。
  Pad
  /// 繰り返す。
  Repeat
  /// 反転して繰り返す。
  Reflect
} derive(Eq)

///|
pub extend ExtendMode with Eq::{not_equal, equal}

///|
pub impl Show for ExtendMode with fn output(self, logger) {
  logger.write_string(
    match self {
      Pad => "Pad"
      Repeat => "Repeat"
      Reflect => "Reflect"
    },
  )
}

///|
pub extend ExtendMode with Show::{to_string, output}

///|
/// Linear Gradient の定義値。Blend2D の BLLinearGradientValues に対応。
pub(all) struct LinearGradientValues {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
} derive(Eq, Debug)

///|
pub extend LinearGradientValues with Eq::{not_equal, equal}

///|
pub extend LinearGradientValues with @debug.Debug::{to_repr}

///|
/// Radial Gradient の定義値。Blend2D の BLRadialGradientValues に対応。
/// (x0,y0,r0) が中心、(x1,y1,r1) が焦点側。現行の補間では r0/center のみを使う。
pub(all) struct RadialGradientValues {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
  r0 : Double
  r1 : Double
} derive(Eq, Debug)

///|
pub extend RadialGradientValues with Eq::{not_equal, equal}

///|
pub extend RadialGradientValues with @debug.Debug::{to_repr}

///|
/// Conic Gradient の定義値。Blend2D の BLConicGradientValues に対応。
pub(all) struct ConicGradientValues {
  x0 : Double
  y0 : Double
  angle : Double
} derive(Eq, Debug)

///|
pub extend ConicGradientValues with Eq::{not_equal, equal}

///|
pub extend ConicGradientValues with @debug.Debug::{to_repr}

///|
/// グラデーションの種別。
pub(all) enum GradientValues {
  Linear(LinearGradientValues)
  Radial(RadialGradientValues)
  Conic(ConicGradientValues)
} derive(Eq, Debug)

///|
pub extend GradientValues with Eq::{not_equal, equal}

///|
pub extend GradientValues with @debug.Debug::{to_repr}

///|
/// グラデーション。
/// 色停止点と拡張モードを保持する。座標はユーザー空間で指定する。
/// 描画時に Context の変換行列を反映した PreparedGradient に変換される。
pub struct Gradient {
  values : GradientValues
  stops : Array[GradientStop]
  mut extend_mode : ExtendMode
}

///|
/// Linear Gradient を生成する。
pub fn Gradient::new_linear(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Gradient {
  { values: Linear({ x0, y0, x1, y1, }), stops: [], extend_mode: Pad, }
}

///|
/// Radial Gradient を生成する。
pub fn Gradient::new_radial(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  r0 : Double,
  r1 : Double,
) -> Gradient {
  { values: Radial({ x0, y0, x1, y1, r0, r1, }), stops: [], extend_mode: Pad, }
}

///|
/// Conic Gradient を生成する。
pub fn Gradient::new_conic(
  x0 : Double,
  y0 : Double,
  angle : Double,
) -> Gradient {
  { values: Conic({ x0, y0, angle, }), stops: [], extend_mode: Pad, }
}

///|
/// 色停止点を追加する。offset は 0.0-1.0 にクランプされ、
/// 追加後に offset 昇順で安定ソートされる (上流 `add_stop` と同じ)。
pub fn Gradient::add_stop(
  self : Gradient,
  offset : Double,
  color : Rgba32,
) -> Gradient {
  self.stops.push({ offset: clamp_f64(offset, 0.0, 1.0), color, })
  // 上流は挿入ごとに安定ソートする (partial_cmp unwrap = NaN 非考慮)。
  self.stops.sort_by(fn(a, b) {
    if a.offset < b.offset {
      -1
    } else if a.offset > b.offset {
      1
    } else {
      0
    }
  })
  self
}

///|
/// 拡張モードを設定する。
pub fn Gradient::set_extend_mode(
  self : Gradient,
  mode : ExtendMode,
) -> Gradient {
  self.extend_mode = mode
  self
}

///|
pub fn Gradient::values(self : Gradient) -> GradientValues {
  self.values
}

///|
pub fn Gradient::stops(self : Gradient) -> ArrayView[GradientStop] {
  self.stops[:]
}

///|
pub fn Gradient::extend_mode(self : Gradient) -> ExtendMode {
  self.extend_mode
}

///|
/// 内容を複製する (set_fill_style_gradient 時のスナップショット用)。
fn Gradient::copy(self : Gradient) -> Gradient {
  {
    values: self.values,
    stops: self.stops.copy(),
    extend_mode: self.extend_mode,
  }
}

// =============================================================================
// 内部型
// =============================================================================

///|
/// LUT サイズ。Blend2D のデフォルトに合わせる。
let lut_size : Int32 = 256

///|
/// 固定小数点の小数ビット数 (16.48 形式)。
let frac_bits : Int32 = 16

///|
/// 描画用に事前計算されたグラデーション状態。
priv struct PreparedGradient {
  lut : FixedArray[UInt32]
  extend_mode : ExtendMode
  kind : PreparedGradientKind
  /// LUT の全エントリが完全不透明 (alpha=255) かどうか。
  /// true の場合、SrcOver 合成を省略して直接ストアできる。
  lut_opaque : Bool
}

///|
priv enum PreparedGradientKind {
  /// dt_dx/dt_dy: デバイス空間での t の増分。t_origin: (0,0) での t。
  Linear(dt_dx~ : Double, dt_dy~ : Double, t_origin~ : Double)
  /// デバイス→ユーザー変換係数。du*_d* は増分、u*_origin は原点値。
  Radial(
    cx~ : Double,
    cy~ : Double,
    r0~ : Double,
    inv_r_diff~ : Double,
    dux_dx~ : Double,
    duy_dx~ : Double,
    dux_dy~ : Double,
    duy_dy~ : Double,
    ux_origin~ : Double,
    uy_origin~ : Double
  )
  Conic(
    cx~ : Double,
    cy~ : Double,
    angle_offset~ : Double,
    dux_dx~ : Double,
    duy_dx~ : Double,
    dux_dy~ : Double,
    duy_dy~ : Double,
    ux_origin~ : Double,
    uy_origin~ : Double
  )
}

///|
/// 描画用に事前計算されたグラデーション状態を生成する。
/// `matrix` は Context の変換行列 (ユーザー空間 → デバイス空間)。
/// グラデーション座標をデバイス空間に変換するために逆行列を使用する。
fn Gradient::prepare(self : Gradient, matrix : Matrix2D) -> PreparedGradient {
  let lut = generate_lut(self.stops)
  let inv = matrix.invert().unwrap_or(Matrix2D::identity())
  let kind = match self.values {
    Linear(v) => {
      let dx = v.x1 - v.x0
      let dy = v.y1 - v.y0
      let len_sq = dx * dx + dy * dy
      if len_sq < 0.0000000001 {
        // 退化: 開始色で塗りつぶす (係数はすべて 0)
        PreparedGradientKind::Linear(dt_dx=0.0, dt_dy=0.0, t_origin=0.0)
      } else {
        // ユーザー空間での係数: t = a*ux + b*uy + c
        let a = dx / len_sq
        let b = dy / len_sq
        let c = -(v.x0 * dx + v.y0 * dy) / len_sq
        // デバイス空間での係数に変換
        PreparedGradientKind::Linear(
          dt_dx=a * inv.m00 + b * inv.m01,
          dt_dy=a * inv.m10 + b * inv.m11,
          t_origin=a * inv.m20 + b * inv.m21 + c,
        )
      }
    }
    GradientValues::Radial(v) => {
      let r_diff = v.r1 - v.r0
      let inv_r_diff = if r_diff.abs() < 0.0000000001 {
        0.0
      } else {
        1.0 / r_diff
      }
      PreparedGradientKind::Radial(
        cx=v.x0,
        cy=v.y0,
        r0=v.r0,
        inv_r_diff~,
        dux_dx=inv.m00,
        duy_dx=inv.m01,
        dux_dy=inv.m10,
        duy_dy=inv.m11,
        ux_origin=inv.m20,
        uy_origin=inv.m21,
      )
    }
    Conic(v) =>
      PreparedGradientKind::Conic(
        cx=v.x0,
        cy=v.y0,
        angle_offset=v.angle,
        dux_dx=inv.m00,
        duy_dx=inv.m01,
        dux_dy=inv.m10,
        duy_dy=inv.m11,
        ux_origin=inv.m20,
        uy_origin=inv.m21,
      )
  }
  let mut lut_opaque = true
  for c in lut {
    if c >> 24 != 0xFF {
      lut_opaque = false
      break
    }
  }
  { lut, extend_mode: self.extend_mode, kind, lut_opaque, }
}

// =============================================================================
// スパン fetch (fill_path 用)
// =============================================================================

///|
/// スパンのグラデーション色を計算して `span` に書き込む。
/// `fetch_span_linear_fixed` に対応: Linear は固定小数点、
/// Radial/Conic は f32 累積 (上流 `fetch_span`)。
/// (x_start, y) はデバイス座標。ピクセル中心 (+0.5) を使用する。
fn PreparedGradient::fetch_span(
  self : PreparedGradient,
  x_start : Int32,
  y : Int32,
  span : FixedArray[UInt32],
) -> Unit {
  match self.kind {
    PreparedGradientKind::Linear(dt_dx~, dt_dy~, t_origin~) =>
      // Linear は固定小数点経路 (fill_rect と同じ t 計算)。
      self.fetch_span_linear_fixed(x_start, y, span, dt_dx, dt_dy, t_origin)
    PreparedGradientKind::Radial(
      cx~,
      cy~,
      r0~,
      inv_r_diff~,
      dux_dx~,
      duy_dx~,
      dux_dy~,
      duy_dy~,
      ux_origin~,
      uy_origin~
    ) => {
      // f32 に変換して内部ループを高速化する (上流同様)
      let cx_f = Float::from_double(cx)
      let cy_f = Float::from_double(cy)
      let r0_f = Float::from_double(r0)
      let inv_r_diff_f = Float::from_double(inv_r_diff)
      let dux_dx_f = Float::from_double(dux_dx)
      let duy_dx_f = Float::from_double(duy_dx)
      let max_idx_f = Float::from_int(lut_size - 1)
      let px0 = x_start.to_double() + 0.5
      let py = y.to_double() + 0.5
      let mut ux = Float::from_double(dux_dx * px0 + dux_dy * py + ux_origin)
      let mut uy = Float::from_double(duy_dx * px0 + duy_dy * py + uy_origin)
      for i in 0..<span.length() {
        let dx = ux - cx_f
        let dy = uy - cy_f
        let dist = (dx * dx + dy * dy).sqrt()
        // 上流は (v.clamp(0.0, max)) as usize = 飽和切り捨て
        let idx_f = ((dist - r0_f) * inv_r_diff_f * max_idx_f).clamp(
          min=0.0,
          max=max_idx_f,
        )
        span[i] = self.lut[idx_f.to_int()]
        ux += dux_dx_f
        uy += duy_dx_f
      }
    }
    PreparedGradientKind::Conic(
      cx~,
      cy~,
      angle_offset~,
      dux_dx~,
      duy_dx~,
      dux_dy~,
      duy_dy~,
      ux_origin~,
      uy_origin~
    ) => {
      let cx_f = Float::from_double(cx)
      let cy_f = Float::from_double(cy)
      let angle_off_f = Float::from_double(angle_offset)
      let dux_dx_f = Float::from_double(dux_dx)
      let duy_dx_f = Float::from_double(duy_dx)
      let inv_2pi_f : Float = Float::from_double(
        1.0 / (2.0 * 3.141592653589793),
      )
      let max_idx_f = Float::from_int(lut_size - 1)
      let px0 = x_start.to_double() + 0.5
      let py = y.to_double() + 0.5
      let mut ux = Float::from_double(dux_dx * px0 + dux_dy * py + ux_origin)
      let mut uy = Float::from_double(duy_dx * px0 + duy_dy * py + uy_origin)
      for i in 0..<span.length() {
        let dx = ux - cx_f
        let dy = uy - cy_f
        let angle = fast_atan2_f32(dy, dx) - angle_off_f
        let t = angle * inv_2pi_f
        let idx = ((t - t.floor()) * max_idx_f).to_int()
        span[i] = self.lut[@cmp.minimum(idx, lut_size - 1)]
        ux += dux_dx_f
        uy += duy_dx_f
      }
    }
  }
}

///|
/// Linear グラデーションのスパンを固定小数点で計算する。
/// 上流 `fetch_span_linear_fixed` に対応 (全 extend mode で固定小数点)。
fn PreparedGradient::fetch_span_linear_fixed(
  self : PreparedGradient,
  x_start : Int32,
  y : Int32,
  span : FixedArray[UInt32],
  dt_dx : Double,
  dt_dy : Double,
  t_origin : Double,
) -> Unit {
  let max_idx = (lut_size - 1).to_double()
  let scale = max_idx * (1 << frac_bits).to_double()
  let dt_dx_fixed = (dt_dx * scale).to_int64()
  // 上流は t_start を f64 で計算してから i64 に変換する
  let mut t = ((
    dt_dx * (x_start.to_double() + 0.5) +
    dt_dy * (y.to_double() + 0.5) +
    t_origin
  ) *
  scale).to_int64()
  let max_fixed = (lut_size.to_int64() - 1) << frac_bits
  let cycle_mask = (lut_size.to_uint64() << frac_bits) - 1
  let cycle2_mask = ((lut_size.to_uint64() * 2) << frac_bits) - 1
  match self.extend_mode {
    Pad =>
      for i in 0..<span.length() {
        let idx = clamp_i64(t, 0, max_fixed) >> frac_bits
        span[i] = self.lut[idx.to_int()]
        t += dt_dx_fixed
      }
    Repeat =>
      for i in 0..<span.length() {
        let idx = ((t.reinterpret_as_uint64() & cycle_mask) >> frac_bits).to_int()
        span[i] = self.lut[idx]
        t += dt_dx_fixed
      }
    Reflect =>
      for i in 0..<span.length() {
        let t_abs = unsigned_abs_i64(t)
        let t_mod = ((t_abs & cycle2_mask) >> frac_bits).to_int()
        let idx = if t_mod > 255 { 511 - t_mod } else { t_mod }
        span[i] = self.lut[idx]
        t += dt_dx_fixed
      }
  }
}

// =============================================================================
// fill_rect (ボックス直接描画)
// =============================================================================

///|
/// グラデーションを矩形に直接描画する (融合 fetch + blend)。
/// 上流同様 comp_op は参照しない (不透明 LUT → 直接ストア、半透明 → SrcOver)。
/// dst はピクセル (0xAARRGGBB) 配列ではなくバイト列へのオフセットで扱う。
fn PreparedGradient::fill_rect(
  self : PreparedGradient,
  img : Image,
  x0 : Int32,
  y0 : Int32,
  width : Int32,
  height : Int32,
) -> Unit {
  match self.kind {
    PreparedGradientKind::Linear(dt_dx~, dt_dy~, t_origin~) =>
      self.fill_rect_linear(img, x0, y0, width, height, dt_dx, dt_dy, t_origin)
    PreparedGradientKind::Radial(
      cx~,
      cy~,
      r0~,
      inv_r_diff~,
      dux_dx~,
      duy_dx~,
      dux_dy~,
      duy_dy~,
      ux_origin~,
      uy_origin~
    ) =>
      self.fill_rect_radial(
        img, x0, y0, width, height, cx, cy, r0, inv_r_diff, dux_dx, duy_dx, dux_dy,
        duy_dy, ux_origin, uy_origin,
      )
    PreparedGradientKind::Conic(
      cx~,
      cy~,
      angle_offset~,
      dux_dx~,
      duy_dx~,
      dux_dy~,
      duy_dy~,
      ux_origin~,
      uy_origin~
    ) =>
      self.fill_rect_conic(
        img, x0, y0, width, height, cx, cy, angle_offset, dux_dx, duy_dx, dux_dy,
        duy_dy, ux_origin, uy_origin,
      )
  }
}

///|
/// Linear グラデーションを矩形に直接描画する (16.48 固定小数点)。
fn PreparedGradient::fill_rect_linear(
  self : PreparedGradient,
  img : Image,
  x0 : Int32,
  y0 : Int32,
  width : Int32,
  height : Int32,
  dt_dx : Double,
  dt_dy : Double,
  t_origin : Double,
) -> Unit {
  let max_idx = (lut_size - 1).to_double()
  let scale = max_idx * (1 << frac_bits).to_double()
  let dt_dx_fixed = (dt_dx * scale).to_int64()
  let dt_dy_fixed = (dt_dy * scale).to_int64()
  // 最初の行、最初のピクセル中心での t (固定小数点)
  let t_row0 = ((
    dt_dx * (x0.to_double() + 0.5) + dt_dy * (y0.to_double() + 0.5) + t_origin
  ) *
  scale).to_int64()
  let stride = img.stride()
  let max_fixed = (lut_size.to_int64() - 1) << frac_bits
  let cycle_mask = (lut_size.to_uint64() << frac_bits) - 1
  let cycle2_mask = ((lut_size.to_uint64() * 2) << frac_bits) - 1
  let lut = self.lut
  let lut_opaque = self.lut_opaque
  let mut t_row = t_row0
  for row in 0..<height {
    let base = (y0 + row) * stride + x0 * 4
    match self.extend_mode {
      Pad => {
        // 上流不透明経路は 4 ピクセルアンロールするが i64 整数累積なので
        // 結果は単純累積と一致する (残りも同じ値列)。
        let mut t = t_row
        for x in 0..<width {
          let idx = clamp_i64(t, 0, max_fixed) >> frac_bits
          let px = lut[idx.to_int()]
          let off = base + x * 4
          if lut_opaque {
            img.write_u32(off, px)
          } else {
            img.write_u32(off, @pixel.comp_src_over(img.read_u32(off), px))
          }
          t += dt_dx_fixed
        }
      }
      Repeat => {
        let mut t = t_row
        for x in 0..<width {
          let idx = ((t.reinterpret_as_uint64() & cycle_mask) >> frac_bits).to_int()
          let px = lut[idx]
          let off = base + x * 4
          if lut_opaque {
            img.write_u32(off, px)
          } else {
            img.write_u32(off, @pixel.comp_src_over(img.read_u32(off), px))
          }
          t += dt_dx_fixed
        }
      }
      Reflect => {
        let mut t = t_row
        for x in 0..<width {
          let t_abs = unsigned_abs_i64(t)
          let t_mod = ((t_abs & cycle2_mask) >> frac_bits).to_int()
          let idx = if t_mod > 255 { 511 - t_mod } else { t_mod }
          let px = lut[idx]
          let off = base + x * 4
          if lut_opaque {
            img.write_u32(off, px)
          } else {
            img.write_u32(off, @pixel.comp_src_over(img.read_u32(off), px))
          }
          t += dt_dx_fixed
        }
      }
    }
    t_row += dt_dy_fixed
  }
}

///|
/// Radial グラデーションを矩形に直接描画する。
/// 不透明 LUT は上流 JIT (`build_radial_row_opaque`) の 4 レーン f32 累積を
/// 再現し、半透明 LUT は上流 `fill_radial_row_blend` の単純累積 + SrcOver。
fn PreparedGradient::fill_rect_radial(
  self : PreparedGradient,
  img : Image,
  x0 : Int32,
  y0 : Int32,
  width : Int32,
  height : Int32,
  cx : Double,
  cy : Double,
  r0 : Double,
  inv_r_diff : Double,
  dux_dx : Double,
  duy_dx : Double,
  dux_dy : Double,
  duy_dy : Double,
  ux_origin : Double,
  uy_origin : Double,
) -> Unit {
  let stride = img.stride()
  let lut = self.lut
  let cx_f = Float::from_double(cx)
  let cy_f = Float::from_double(cy)
  let r0_f = Float::from_double(r0)
  let dux_dx_f = Float::from_double(dux_dx)
  let duy_dx_f = Float::from_double(duy_dx)
  let max_idx_f = Float::from_int(lut_size - 1)
  // JIT 経路 (不透明) は inv_r_diff * max_idx を f64 で事前乗算してから f32 化。
  let inv_r_diff_max_f = Float::from_double(inv_r_diff * max_idx_f.to_double())
  let inv_r_diff_f = Float::from_double(inv_r_diff)
  let px0 = x0.to_double() + 0.5
  let zero_f : Float = 0.0
  if self.lut_opaque {
    // === JIT radial_row 相当 ===
    // 4 レーンのオフセットベクトルを fadd チェーンで構築する。
    let dux2 = dux_dx_f + dux_dx_f
    let duy2 = duy_dx_f + duy_dx_f
    let dux3 = dux2 + dux_dx_f
    let duy3 = duy2 + duy_dx_f
    let dux4 = dux2 + dux2
    let duy4 = duy2 + duy2
    let simd_count = width >> 2
    let remainder = width & 3
    for row in 0..<height {
      let y = y0 + row
      let py = y.to_double() + 0.5
      let ux_start = Float::from_double(dux_dx * px0 + dux_dy * py + ux_origin)
      let uy_start = Float::from_double(duy_dx * px0 + duy_dy * py + uy_origin)
      let base = y * stride + x0 * 4
      // 4 レーンの初期値 (上流は scalar_to_vector + insertlane)。
      let mut ux0 = ux_start
      let mut ux1 = ux_start + dux_dx_f
      let mut ux2 = ux_start + dux2
      let mut ux3 = ux_start + dux3
      let mut uy0 = uy_start
      let mut uy1 = uy_start + duy_dx_f
      let mut uy2 = uy_start + duy2
      let mut uy3 = uy_start + duy3
      for chunk in 0..<simd_count {
        let x = chunk * 4
        // レーン 0..3 をそれぞれ計算し直接ストア。
        let i0 = radial_idx(ux0, uy0, cx_f, cy_f, r0_f, inv_r_diff_max_f)
        let i1 = radial_idx(ux1, uy1, cx_f, cy_f, r0_f, inv_r_diff_max_f)
        let i2 = radial_idx(ux2, uy2, cx_f, cy_f, r0_f, inv_r_diff_max_f)
        let i3 = radial_idx(ux3, uy3, cx_f, cy_f, r0_f, inv_r_diff_max_f)
        img.write_u32(base + x * 4, lut[i0])
        img.write_u32(base + (x + 1) * 4, lut[i1])
        img.write_u32(base + (x + 2) * 4, lut[i2])
        img.write_u32(base + (x + 3) * 4, lut[i3])
        ux0 += dux4
        ux1 += dux4
        ux2 += dux4
        ux3 += dux4
        uy0 += duy4
        uy1 += duy4
        uy2 += duy4
        uy3 += duy4
      }
      // スカラ末尾: 上流はベクトル lane0 の累積値から継続する
      // (= ux_start + simd_count * dux4、以後 dux_dx_f ずつ進める)。
      for i in 0..<remainder {
        let x = width - remainder + i
        let idx = radial_idx(ux0, uy0, cx_f, cy_f, r0_f, inv_r_diff_max_f)
        img.write_u32(base + x * 4, lut[idx])
        ux0 += dux_dx_f
        uy0 += duy_dx_f
      }
    }
  } else {
    // === 半透明行: 単純な逐次累積 + SrcOver ===
    for row in 0..<height {
      let y = y0 + row
      let py = y.to_double() + 0.5
      let mut ux = Float::from_double(dux_dx * px0 + dux_dy * py + ux_origin)
      let mut uy = Float::from_double(duy_dx * px0 + duy_dy * py + uy_origin)
      let base = y * stride + x0 * 4
      for x in 0..<width {
        let dx = ux - cx_f
        let dy = uy - cy_f
        let dist = (dx * dx + dy * dy).sqrt()
        let idx_f = ((dist - r0_f) * inv_r_diff_f * max_idx_f).clamp(
          min=zero_f,
          max=max_idx_f,
        )
        let px = lut[idx_f.to_int()]
        img.write_u32(
          base + x * 4,
          @pixel.comp_src_over(img.read_u32(base + x * 4), px),
        )
        ux += dux_dx_f
        uy += duy_dx_f
      }
    }
  }
}

///|
/// Radial のインデックス計算 (JIT 行経路): `clamp((dist-r0)*irdm, 0, 255)` を
/// 整数化する。上流 JIT の `fcvt_to_sint_sat` はこのツールチェーン組合せでは
/// 切り捨てとして観測される (オラクルとの byte 同一で実証済み)。
fn radial_idx(
  ux : Float,
  uy : Float,
  cx : Float,
  cy : Float,
  r0 : Float,
  inv_r_diff_max : Float,
) -> Int32 {
  let dx = ux - cx
  let dy = uy - cy
  let dist = (dx * dx + dy * dy).sqrt()
  let t = ((dist - r0) * inv_r_diff_max).clamp(min=0.0, max=255.0)
  t.to_int()
}

///|
/// Conic グラデーションを矩形に直接描画する。
/// 上流 `fill_rect_conic`: f32 の 4 ピクセルアンロール + fast_atan2 近似。
fn PreparedGradient::fill_rect_conic(
  self : PreparedGradient,
  img : Image,
  x0 : Int32,
  y0 : Int32,
  width : Int32,
  height : Int32,
  cx : Double,
  cy : Double,
  angle_offset : Double,
  dux_dx : Double,
  duy_dx : Double,
  dux_dy : Double,
  duy_dy : Double,
  ux_origin : Double,
  uy_origin : Double,
) -> Unit {
  let stride = img.stride()
  let lut = self.lut
  let lut_opaque = self.lut_opaque
  let cx_f = Float::from_double(cx)
  let cy_f = Float::from_double(cy)
  let angle_off_f = Float::from_double(angle_offset)
  let dux_dx_f = Float::from_double(dux_dx)
  let duy_dx_f = Float::from_double(duy_dx)
  let inv_2pi_f : Float = Float::from_double(1.0 / (2.0 * 3.141592653589793))
  let max_idx_f = Float::from_int(lut_size - 1)
  let px0 = x0.to_double() + 0.5
  let dux4 = dux_dx_f * 4.0
  let duy4 = duy_dx_f * 4.0
  let simd_width = width / 4
  let remainder = width - simd_width * 4
  for row in 0..<height {
    let y = y0 + row
    let py = y.to_double() + 0.5
    let ux_start = Float::from_double(dux_dx * px0 + dux_dy * py + ux_origin)
    let uy_start = Float::from_double(duy_dx * px0 + duy_dy * py + uy_origin)
    let base = y * stride + x0 * 4
    // 上流はレーン開始値を ux_start + dux*{1,2,3} の fmul で作る。
    let mut ux0 = ux_start
    let mut ux1 = ux_start + dux_dx_f
    let mut ux2 = ux_start + dux_dx_f * 2.0
    let mut ux3 = ux_start + dux_dx_f * 3.0
    let mut uy0 = uy_start
    let mut uy1 = uy_start + duy_dx_f
    let mut uy2 = uy_start + duy_dx_f * 2.0
    let mut uy3 = uy_start + duy_dx_f * 3.0
    for chunk in 0..<simd_width {
      let x = chunk * 4
      let i0 = conic_idx(
        ux0, uy0, cx_f, cy_f, angle_off_f, inv_2pi_f, max_idx_f,
      )
      let i1 = conic_idx(
        ux1, uy1, cx_f, cy_f, angle_off_f, inv_2pi_f, max_idx_f,
      )
      let i2 = conic_idx(
        ux2, uy2, cx_f, cy_f, angle_off_f, inv_2pi_f, max_idx_f,
      )
      let i3 = conic_idx(
        ux3, uy3, cx_f, cy_f, angle_off_f, inv_2pi_f, max_idx_f,
      )
      if lut_opaque {
        img.write_u32(base + x * 4, lut[i0])
        img.write_u32(base + (x + 1) * 4, lut[i1])
        img.write_u32(base + (x + 2) * 4, lut[i2])
        img.write_u32(base + (x + 3) * 4, lut[i3])
      } else {
        img.write_u32(
          base + x * 4,
          @pixel.comp_src_over(img.read_u32(base + x * 4), lut[i0]),
        )
        img.write_u32(
          base + (x + 1) * 4,
          @pixel.comp_src_over(img.read_u32(base + (x + 1) * 4), lut[i1]),
        )
        img.write_u32(
          base + (x + 2) * 4,
          @pixel.comp_src_over(img.read_u32(base + (x + 2) * 4), lut[i2]),
        )
        img.write_u32(
          base + (x + 3) * 4,
          @pixel.comp_src_over(img.read_u32(base + (x + 3) * 4), lut[i3]),
        )
      }
      ux0 += dux4
      ux1 += dux4
      ux2 += dux4
      ux3 += dux4
      uy0 += duy4
      uy1 += duy4
      uy2 += duy4
      uy3 += duy4
    }
    // 余りピクセル: lane0 の累積値から dux_dx_f ずつ進める。
    for i in 0..<remainder {
      let x = width - remainder + i
      let idx = conic_idx(
        ux0, uy0, cx_f, cy_f, angle_off_f, inv_2pi_f, max_idx_f,
      )
      let off = base + x * 4
      if lut_opaque {
        img.write_u32(off, lut[idx])
      } else {
        img.write_u32(off, @pixel.comp_src_over(img.read_u32(off), lut[idx]))
      }
      ux0 += dux_dx_f
      uy0 += duy_dx_f
    }
  }
}

///|
/// Conic のインデックス計算: `((t - floor(t)) * 255) as usize`、255 でクランプ。
fn conic_idx(
  ux : Float,
  uy : Float,
  cx : Float,
  cy : Float,
  angle_off : Float,
  inv_2pi : Float,
  max_idx : Float,
) -> Int32 {
  let dx = ux - cx
  let dy = uy - cy
  let angle = fast_atan2_f32(dy, dx) - angle_off
  let t = angle * inv_2pi
  let idx = ((t - t.floor()) * max_idx).to_int()
  @cmp.minimum(idx, 255)
}

// =============================================================================
// LUT 生成
// =============================================================================

///|
/// 色停止点から PRGB32 形式の LUT を生成する。
/// 0 停止点なら全透明、1 つなら単色。上流 `generate_lut` に対応。
fn generate_lut(stops : Array[GradientStop]) -> FixedArray[UInt32] {
  let lut : FixedArray[UInt32] = FixedArray::make(lut_size, 0)
  if stops.is_empty() {
    return lut
  }
  if stops.length() == 1 {
    lut.fill(stops[0].color.to_prgb32())
    return lut
  }
  for i in 0..<lut_size {
    let t = i.to_double() / (lut_size - 1).to_double()
    lut[i] = interpolate_stops(stops, t)
  }
  lut
}

///|
/// 色停止点間を補間して PRGB32 色を返す。
fn interpolate_stops(stops : Array[GradientStop], t : Double) -> UInt32 {
  if t <= stops[0].offset {
    return stops[0].color.to_prgb32()
  }
  let last = stops.length() - 1
  if t >= stops[last].offset {
    return stops[last].color.to_prgb32()
  }
  for i in 0..<last {
    if t <= stops[i + 1].offset {
      let range = stops[i + 1].offset - stops[i].offset
      if range < 0.0000000001 {
        return stops[i + 1].color.to_prgb32()
      }
      let local_t = (t - stops[i].offset) / range
      return lerp_prgb32(stops[i].color, stops[i + 1].color, local_t)
    }
  }
  stops[last].color.to_prgb32()
}

///|
/// 2 色間を premultiplied ARGB32 空間で線形補間する (8.8 固定小数点)。
fn lerp_prgb32(c0 : Rgba32, c1 : Rgba32, t : Double) -> UInt32 {
  let p0 = c0.to_prgb32()
  let p1 = c1.to_prgb32()
  let t_fixed = (t * 256.0).to_int().reinterpret_as_uint()
  let inv_t : UInt32 = 256 - t_fixed
  let a = (((p0 >> 24) & 0xFF) * inv_t + ((p1 >> 24) & 0xFF) * t_fixed) >> 8
  let r = (((p0 >> 16) & 0xFF) * inv_t + ((p1 >> 16) & 0xFF) * t_fixed) >> 8
  let g = (((p0 >> 8) & 0xFF) * inv_t + ((p1 >> 8) & 0xFF) * t_fixed) >> 8
  let b = ((p0 & 0xFF) * inv_t + (p1 & 0xFF) * t_fixed) >> 8
  (a << 24) | (r << 16) | (g << 8) | b
}

// =============================================================================
// 高速 atan2 近似
// =============================================================================

///|
/// atan2 の多項式近似 (f32)。上流 `fast_atan2_f32` の移植。
/// 標準の atan2 (~50-100 サイクル) の代わりに使われる minimax 近似で、
/// 結果は真の atan2 と数 ULP 異なり得る — 互換性のため忠実に再現する。
fn fast_atan2_f32(y : Float, x : Float) -> Float {
  let ax = x.abs()
  let ay = y.abs()
  if ax < 0.0000001 && ay < 0.0000001 {
    return 0.0
  }
  let (z, base) = if ax >= ay {
    (ay / ax, (0.0 : Float))
  } else {
    // FRAC_PI_2 (f32)
    (ax / ay, Float::from_double(1.5707963267948966))
  }
  let z2 = z * z
  // atan(z) の minimax 多項式
  let mut p : Float = -0.046496475
  p = p * z2 + 0.15931422
  p = p * z2 - 0.32762276
  let result = (p * z2 + 1.0) * z
  let result = if ax >= ay { result } else { base - result }
  let result = if x < 0.0 {
    Float::from_double(3.141592653589793) - result
  } else {
    result
  }
  if y < 0.0 {
    -result
  } else {
    result
  }
}

///|
fn clamp_i64(v : Int64, lo : Int64, hi : Int64) -> Int64 {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// `Int64::unsigned_abs` 相当 (Rust の i64::unsigned_abs)。
/// 負値は 2 の補数を反転する。Int64::MIN は -MIN に wrap しても
/// ビット表現が同じなので正しい値になる。
fn unsigned_abs_i64(v : Int64) -> UInt64 {
  if v < 0 {
    (-v).reinterpret_as_uint64()
  } else {
    v.reinterpret_as_uint64()
  }
}
