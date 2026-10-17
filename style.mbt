///|
/// RGBA カラー値。内部表現は 0xAARRGGBB。
/// 上流 `api/style.rs` の `Rgba32` に対応。
pub(all) struct Rgba32 {
  /// パックドワード (0xAARRGGBB、non-premultiplied)。
  value : UInt32
} derive(Eq, Debug)

///|
pub fn Rgba32::new(r : UInt32, g : UInt32, b : UInt32, a : UInt32) -> Rgba32 {
  {
    value: ((a & 0xFF) << 24) |
    ((r & 0xFF) << 16) |
    ((g & 0xFF) << 8) |
    (b & 0xFF),
  }
}

///|
/// アルファ 255 の不透明色を生成する。
pub fn Rgba32::rgb(r : UInt32, g : UInt32, b : UInt32) -> Rgba32 {
  Rgba32::new(r, g, b, 255)
}

///|
pub fn Rgba32::r(self : Rgba32) -> UInt32 {
  (self.value >> 16) & 0xFF
}

///|
pub fn Rgba32::g(self : Rgba32) -> UInt32 {
  (self.value >> 8) & 0xFF
}

///|
pub fn Rgba32::b(self : Rgba32) -> UInt32 {
  self.value & 0xFF
}

///|
pub fn Rgba32::a(self : Rgba32) -> UInt32 {
  (self.value >> 24) & 0xFF
}

///|
pub fn Rgba32::is_opaque(self : Rgba32) -> Bool {
  self.value >= 0xFF00_0000
}

///|
pub fn Rgba32::is_transparent(self : Rgba32) -> Bool {
  self.value <= 0x00FF_FFFF
}

///|
/// premultiplied ARGB32 (0xAARRGGBB) に変換する。
pub fn Rgba32::to_prgb32(self : Rgba32) -> UInt32 {
  @pixel.premultiply_rgba(self.r(), self.g(), self.b(), self.a())
}

///|
/// パックドワード (0xAARRGGBB) をそのまま返す。
/// テスト・デバッグ用。上流のフィールド公開に相当。
pub fn Rgba32::to_uint(self : Rgba32) -> UInt32 {
  self.value
}

///|
/// ストロークの端点形状。上流 `StrokeCap` に対応。
pub(all) enum StrokeCap {
  /// 端点で切り落とし (デフォルト)。
  Butt
  /// 端点を width/2 だけ延長した矩形。
  Square
  /// 端点に半円を付加する。
  Round
} derive(Eq, Debug)

///|
/// ストロークの接続形状。Blend2D の BLStrokeJoin と値を合わせている。
pub(all) enum StrokeJoin {
  /// マイター接合 (miter limit 超過時に切り落とし、Blend2D デフォルト)。
  MiterClip
  /// マイター接合 (miter limit 超過時に Bevel にフォールバック)。
  MiterBevel
  /// マイター接合 (miter limit 超過時に Round にフォールバック)。
  MiterRound
  /// 斜め切り落とし。
  Bevel
  /// 円弧接合。
  Round
} derive(Eq, Debug)

///|
/// 塗りつぶし規則。パスの内外判定アルゴリズムを決定する。
pub(all) enum FillRule {
  /// ワインディングナンバーが非ゼロなら内側 (デフォルト)。
  NonZero
  /// ワインディングナンバーが奇数なら内側。
  EvenOdd
} derive(Eq, Debug)

///|
/// 合成オペレーション。Blend2D の BLCompOp と値を合わせている。
/// 上流 `CompOp` に対応 (全 29 種)。
pub(all) enum CompOp {
  /// source を destination の上に Porter-Duff SrcOver で合成する。
  /// out = src + dst * (1 - srcA)
  SrcOver
  /// destination を source で完全に置き換える。
  /// out = src
  SrcCopy
  /// out = src * dstA
  SrcIn
  /// out = src * (1 - dstA)
  SrcOut
  /// out = src * dstA + dst * (1 - srcA)
  SrcAtop
  /// out = dst + src * (1 - dstA)
  DstOver
  /// out = dst (何もしない)
  DstCopy
  /// out = dst * srcA
  DstIn
  /// out = dst * (1 - srcA)
  DstOut
  /// out = dst * srcA + src * (1 - dstA)
  DstAtop
  /// out = src * (1 - dstA) + dst * (1 - srcA)
  Xor
  /// out = 0
  Clear
  /// out = min(src + dst, 1)
  Plus
  /// out = max(dst - src, 0), alpha = SrcOver
  Minus
  /// out_c = src_c * dst_c / 255 (チャネル乗算、alpha も同様)
  Modulate
  /// Multiply ブレンド。blend = src*dst, out = blend + src*(1-dstA) + dst*(1-srcA)
  Multiply
  /// Screen ブレンド。out = src + dst - src*dst
  Screen
  /// Overlay ブレンド。条件分岐 (2*Dc < Da)
  Overlay
  /// Darken ブレンド。blend = min(src*dstA, dst*srcA)
  Darken
  /// Lighten ブレンド。blend = max(src*dstA, dst*srcA)
  Lighten
  /// ColorDodge ブレンド。除算あり
  ColorDodge
  /// ColorBurn ブレンド。除算あり
  ColorBurn
  /// LinearBurn ブレンド。飽和減算
  LinearBurn
  /// LinearLight ブレンド。clamp + 条件
  LinearLight
  /// PinLight ブレンド。条件分岐 + min/max
  PinLight
  /// HardLight ブレンド。条件分岐 (2*Sc < Sa)
  HardLight
  /// SoftLight ブレンド。除算 + sqrt + 条件分岐
  SoftLight
  /// Difference ブレンド。abs 差分
  Difference
  /// Exclusion ブレンド。単純な算術
  Exclusion
} derive(Eq, Debug)

///|
pub extend Rgba32 with Eq::{not_equal, equal}

///|
pub extend Rgba32 with @debug.Debug::{to_repr}

///|
pub extend StrokeCap with Eq::{not_equal, equal}

///|
pub extend StrokeCap with @debug.Debug::{to_repr}

///|
pub extend StrokeJoin with Eq::{not_equal, equal}

///|
pub extend StrokeJoin with @debug.Debug::{to_repr}

///|
pub extend FillRule with Eq::{not_equal, equal}

///|
pub extend FillRule with @debug.Debug::{to_repr}

///|
/// エラーメッセージ・ログ用の表示名。上流の enum 名と揃える。
impl Show for CompOp with fn output(self, l) {
  let s = match self {
    SrcOver => "SrcOver"
    SrcCopy => "SrcCopy"
    SrcIn => "SrcIn"
    SrcOut => "SrcOut"
    SrcAtop => "SrcAtop"
    DstOver => "DstOver"
    DstCopy => "DstCopy"
    DstIn => "DstIn"
    DstOut => "DstOut"
    DstAtop => "DstAtop"
    Xor => "Xor"
    Clear => "Clear"
    Plus => "Plus"
    Minus => "Minus"
    Modulate => "Modulate"
    Multiply => "Multiply"
    Screen => "Screen"
    Overlay => "Overlay"
    Darken => "Darken"
    Lighten => "Lighten"
    ColorDodge => "ColorDodge"
    ColorBurn => "ColorBurn"
    LinearBurn => "LinearBurn"
    LinearLight => "LinearLight"
    PinLight => "PinLight"
    HardLight => "HardLight"
    SoftLight => "SoftLight"
    Difference => "Difference"
    Exclusion => "Exclusion"
  }
  l.write_string(s)
}

///|
pub extend CompOp with Show::{to_string, output}

///|
pub extend CompOp with Eq::{not_equal, equal}

///|
pub extend CompOp with @debug.Debug::{to_repr}
