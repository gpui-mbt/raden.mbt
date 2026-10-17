///|
/// pattern.mbt -- 画像パターン
///
/// 上流 `src/api/pattern.rs` の移植。Blend2D の BLPattern に対応。
/// ソース画像の一部または全体をタイルとして繰り返す。
///
/// 注意: 上流と同じくサンプリング座標は「ピクセル中心 +0.5 ではなく
/// 整数のデバイス座標」をテクスチャ変換に通す (fetch_span も同様)。

///|
/// パターンの補間モード。
pub(all) enum PatternFilter {
  /// 最近傍。
  Nearest
  /// 双一次補間。
  Bilinear
} derive(Eq)

///|
pub extend PatternFilter with Eq::{not_equal, equal}

///|
pub impl Show for PatternFilter with fn output(self, logger) {
  logger.write_string(if self is Nearest { "Nearest" } else { "Bilinear" })
}

///|
pub extend PatternFilter with Show::{to_string, output}

///|
/// 画像パターン。
/// ソース画像のピクセルデータ (PRGB32, 4 バイト/ピクセル) を保持する。
pub struct Pattern {
  /// ソース画像のピクセルデータ (PRGB32, 4 バイト/ピクセル)。
  /// `set_fill_style_pattern` 時点ではなくコンストラクト時のスナップショット。
  data : Bytes
  /// ソース画像の幅。
  width : Int32
  /// ソース画像の高さ。
  height : Int32
  /// ソース画像のストライド (バイト単位)。
  src_stride : Int32
  /// ユーザ空間からテクスチャ空間 (連続座標) への変換。
  /// 既定は単位行列。`set_origin` は `translation(-tx, -ty)` に相当する。
  mut transform : Matrix2D
  /// 補間モード。
  mut filter : PatternFilter
  /// 拡張モード。
  mut extend_mode : ExtendMode
}

///|
/// Image のデータからパターンを生成する。
///
/// `data` は PRGB32 形式のピクセルデータ、`stride` はソース画像のストライド
/// (バイト単位)。`data.length() < stride * height` でもエラーにせず、
/// 上流同様に読み出し時に範囲外アクセスしない前提で扱う
/// (十分な長さがなければ描画時に不正ピクセルとなるため呼び出し側の責任)。
pub fn Pattern::new(
  data : Bytes,
  width : Int32,
  height : Int32,
  stride : Int32,
) -> Pattern {
  {
    data,
    width,
    height,
    src_stride: stride,
    transform: Matrix2D::identity(),
    filter: Nearest,
    extend_mode: Repeat,
  }
}

///|
/// Image からパターンを生成する (Prgb32/Xrgb32 ソースのみ)。
/// 4 バイト/ピクセルのバイト列をそのままスナップショットする。
pub fn Pattern::from_image(image : Image) -> Pattern raise RadenError {
  match image.format() {
    A8 =>
      raise UnsupportedFeature(
        "Pattern::from_image requires a 4-byte-per-pixel image",
      )
    _ =>
      Pattern::new(
        image.data().to_owned(),
        image.width(),
        image.height(),
        image.stride(),
      )
  }
}

///|
/// パターンの原点オフセットを設定する。
///
/// デバイス座標 (dx, dy) でテクスチャ (0,0) が現れる位置を (tx, ty) に合わせる。
/// 内部では `transform = translation(-tx, -ty)` として扱う。
/// `set_transform` と併用する場合、呼び出し順に依存せず、
/// 後から呼んだ方が `transform` 全体を置き換える (上流同様)。
pub fn Pattern::set_origin(self : Pattern, tx : Double, ty : Double) -> Pattern {
  self.transform = Matrix2D::translation(-tx, -ty)
  self
}

///|
/// パターンの変換行列を設定する (ユーザ空間→テクスチャ空間)。
pub fn Pattern::set_transform(self : Pattern, m : Matrix2D) -> Pattern {
  self.transform = m
  self
}

///|
/// 補間モードを設定する。
pub fn Pattern::set_filter(self : Pattern, filter : PatternFilter) -> Pattern {
  self.filter = filter
  self
}

///|
/// 拡張モードを設定する。
pub fn Pattern::set_extend_mode(self : Pattern, mode : ExtendMode) -> Pattern {
  self.extend_mode = mode
  self
}

///|
pub fn Pattern::width(self : Pattern) -> Int32 {
  self.width
}

///|
pub fn Pattern::height(self : Pattern) -> Int32 {
  self.height
}

///|
pub fn Pattern::extend_mode(self : Pattern) -> ExtendMode {
  self.extend_mode
}

///|
pub fn Pattern::filter(self : Pattern) -> PatternFilter {
  self.filter
}

///|
pub fn Pattern::transform(self : Pattern) -> Matrix2D {
  self.transform
}

///|
/// 内部複製 (`set_fill_style_pattern` 等のスナップショット用)。
/// `data` は Bytes (不変) のため共有してよい。
fn Pattern::copy(self : Pattern) -> Pattern {
  {
    data: self.data,
    width: self.width,
    height: self.height,
    src_stride: self.src_stride,
    transform: self.transform,
    filter: self.filter,
    extend_mode: self.extend_mode,
  }
}

// =============================================================================
// PreparedPattern
// =============================================================================

///|
/// 描画用に事前計算されたパターン状態。
priv struct PreparedPattern {
  data : Bytes
  width : Int32
  height : Int32
  src_stride : Int32
  extend_mode : ExtendMode
  /// 全ピクセルが不透明 (byte[3] == 0xFF) かどうか。
  is_opaque : Bool
  /// デバイス座標からテクスチャ空間 (連続) への変換。
  to_tex : Matrix2D
  filter : PatternFilter
}

///|
/// 描画用に事前計算されたパターン状態を生成する。
/// `matrix` は Context のユーザ→デバイス行列。
/// `pattern.transform * inv(matrix)` でデバイス座標からテクスチャ座標へ写す。
fn Pattern::prepare(self : Pattern, matrix : Matrix2D) -> PreparedPattern {
  // 上流はバッファ全体を chunks_exact(4) で走査する (ストライドの
  // パディングも 4 バイトチャンクとして判定対象に含まれる)。
  // 末尾の 4 バイト未満は無視される。
  let mut is_opaque = true
  let nbytes = self.data.length()
  let mut off = 3
  while off + 1 <= nbytes {
    // chunks_exact(4) の各チャンクの byte[3] (アルファ) を検査する。
    if self.data[off].to_uint() != 0xFF {
      is_opaque = false
      break
    }
    off += 4
  }
  let inv = matrix.invert().unwrap_or(Matrix2D::identity())
  let to_tex = self.transform.multiply(inv)
  {
    data: self.data,
    width: self.width,
    height: self.height,
    src_stride: self.src_stride,
    extend_mode: self.extend_mode,
    is_opaque,
    to_tex,
    filter: self.filter,
  }
}

///|
/// パターンを矩形に直接描画する (融合 fetch + blend)。
/// comp_op は SrcCopy/SrcOver のみ対応 (上流同様、それ以外は panic に相当する
/// `UnsupportedFeature` を送出する)。
fn PreparedPattern::fill_rect(
  self : PreparedPattern,
  img : Image,
  comp_op : CompOp,
  x0 : Int32,
  y0 : Int32,
  width : Int32,
  height : Int32,
) -> Unit raise RadenError {
  let sw = self.width
  let sh = self.height
  if sw <= 0 || sh <= 0 {
    return
  }
  // 上流は未対応 comp_op を最初のピクセル書き込み時に panic する。
  // 描画対象が 1 ピクセルも無ければ panic しないため、
  // ここでも「実際に書き込む矩形が空でない」場合のみ検証する。
  if width > 0 && height > 0 && comp_op != SrcCopy && comp_op != SrcOver {
    raise UnsupportedFeature(
      "CompOp \{comp_op} is not supported for pattern fill_rect; use SrcOver, SrcCopy, or fill_path",
    )
  }
  let stride = img.stride()
  for row in 0..<height {
    let dy = y0 + row
    let base = dy * stride
    for x in 0..<width {
      let dx = x0 + x
      let (tx, ty) = self.to_tex.map_point(dx.to_double(), dy.to_double())
      let pixel = self.sample_prgb32(tx, ty)
      let off = base + (x0 + x) * 4
      if comp_op == SrcCopy {
        img.write_u32(off, pixel)
      } else if self.is_opaque {
        img.write_u32(off, pixel)
      } else {
        img.write_u32(off, @pixel.comp_src_over(img.read_u32(off), pixel))
      }
    }
  }
}

///|
/// パターンスパンを計算して `span` に書き込む。fill_path 用。
/// 合成は呼び出し側の span_cov パイプラインが行う (comp_op を参照しない)。
fn PreparedPattern::fetch_span(
  self : PreparedPattern,
  x_start : Int32,
  y : Int32,
  span : FixedArray[UInt32],
) -> Unit {
  let sw = self.width
  let sh = self.height
  if sw <= 0 || sh <= 0 {
    span.fill(0)
    return
  }
  let yd = y.to_double()
  for i in 0..<span.length() {
    let dx = x_start + i
    let (tx, ty) = self.to_tex.map_point(dx.to_double(), yd)
    span[i] = self.sample_prgb32(tx, ty)
  }
}

///|
fn PreparedPattern::sample_prgb32(
  self : PreparedPattern,
  tx : Double,
  ty : Double,
) -> UInt32 {
  match self.filter {
    Nearest => self.sample_nearest(tx, ty)
    Bilinear => self.sample_bilinear(tx, ty)
  }
}

///|
fn PreparedPattern::read_px(
  self : PreparedPattern,
  sx : Int32,
  sy : Int32,
) -> UInt32 {
  // PRGB32 リトルエンディアン: [B, G, R, A]
  let off = sy * self.src_stride + sx * 4
  let b = self.data[off].to_uint()
  let g = self.data[off + 1].to_uint()
  let r = self.data[off + 2].to_uint()
  let a = self.data[off + 3].to_uint()
  (a << 24) | (r << 16) | (g << 8) | b
}

///|
fn PreparedPattern::sample_nearest(
  self : PreparedPattern,
  tx : Double,
  ty : Double,
) -> UInt32 {
  let sx = self.nearest_index(tx, self.width)
  let sy = self.nearest_index(ty, self.height)
  self.read_px(sx, sy)
}

///|
/// 連続座標を最近傍ピクセルインデックスに変換する (拡張モード適用)。
fn PreparedPattern::nearest_index(
  self : PreparedPattern,
  coord : Double,
  size : Int32,
) -> Int32 {
  let s = size.to_double()
  match self.extend_mode {
    Pad => {
      let c = clamp_f64(coord, 0.0, s - 1.0)
      (c + 0.5).floor().to_int()
    }
    Repeat => {
      let u = rem_euclid(coord, s)
      let idx = (u + 0.5).floor().to_int()
      idx % size // rem_euclid と同等 (idx >= 0、size > 0)
    }
    Reflect => {
      let u = reflect_coord_float(coord, s)
      clamp_f64((u + 0.5).floor(), 0.0, s - 1.0).to_int()
    }
  }
}

///|
fn PreparedPattern::sample_bilinear(
  self : PreparedPattern,
  tx : Double,
  ty : Double,
) -> UInt32 {
  let w = self.width
  let h = self.height
  let wf = w.to_double()
  let hf = h.to_double()
  match self.extend_mode {
    Pad => {
      let px = clamp_f64(tx, 0.0, wf - 1.0)
      let py = clamp_f64(ty, 0.0, hf - 1.0)
      let x0 = px.floor().to_int()
      let y0 = py.floor().to_int()
      let x1 = @cmp.minimum(x0 + 1, w - 1)
      let y1 = @cmp.minimum(y0 + 1, h - 1)
      let fx = px - x0.to_double()
      let fy = py - y0.to_double()
      self.bilerp(x0, y0, x1, y1, fx, fy)
    }
    Repeat => self.bilinear_repeat(rem_euclid(tx, wf), rem_euclid(ty, hf))
    Reflect => {
      let px = reflect_coord_float(tx, wf)
      let py = reflect_coord_float(ty, hf)
      let x0 = px.floor().to_int()
      let y0 = py.floor().to_int()
      let x1 = @cmp.minimum(x0 + 1, w - 1)
      let y1 = @cmp.minimum(y0 + 1, h - 1)
      let fx = px - x0.to_double()
      let fy = py - y0.to_double()
      self.bilerp(x0, y0, x1, y1, fx, fy)
    }
  }
}

///|
fn PreparedPattern::bilerp(
  self : PreparedPattern,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
  fx : Double,
  fy : Double,
) -> UInt32 {
  let c00 = self.read_px(x0, y0)
  let c10 = self.read_px(x1, y0)
  let c01 = self.read_px(x0, y1)
  let c11 = self.read_px(x1, y1)
  lerp_rgba_premul(c00, c10, c01, c11, fx, fy)
}

///|
/// Repeat モードの双一次補間: 端でラップする。
fn PreparedPattern::bilinear_repeat(
  self : PreparedPattern,
  px : Double,
  py : Double,
) -> UInt32 {
  let w = self.width
  let h = self.height
  let x0 = px.floor().to_int()
  let y0 = py.floor().to_int()
  let fx = px - x0.to_double()
  let fy = py - y0.to_double()
  let x1 = rem_euclid_i32(x0 + 1, w)
  let y1 = rem_euclid_i32(y0 + 1, h)
  let x0w = rem_euclid_i32(x0, w)
  let y0w = rem_euclid_i32(y0, h)
  let c00 = self.read_px(x0w, y0w)
  let c10 = self.read_px(x1, y0w)
  let c01 = self.read_px(x0w, y1)
  let c11 = self.read_px(x1, y1)
  lerp_rgba_premul(c00, c10, c01, c11, fx, fy)
}

///|
/// 反射モード用: 連続座標を [0, size) に折り返す。
fn reflect_coord_float(coord : Double, size : Double) -> Double {
  if size <= 1.0 {
    return 0.0
  }
  let double_ = size * 2.0
  let c = rem_euclid(coord, double_)
  if c >= size {
    double_ - 1.0 - c
  } else {
    c
  }
}

///|
/// Rust の f64::rem_euclid: `x % s` の剰余を [0, |s|) に正規化する。
fn rem_euclid(x : Double, s : Double) -> Double {
  let r = x % s
  if r < 0.0 {
    r + s.abs()
  } else {
    r
  }
}

///|
/// i32 版 rem_euclid (size > 0 前提)。
fn rem_euclid_i32(x : Int32, size : Int32) -> Int32 {
  let r = x % size
  if r < 0 {
    r + size
  } else {
    r
  }
}

///|
/// PRGB32 前提の双一次補間 (チャンネルごとに線形、結果は丸めて整数に戻す)。
fn lerp_rgba_premul(
  c00 : UInt32,
  c10 : UInt32,
  c01 : UInt32,
  c11 : UInt32,
  fx : Double,
  fy : Double,
) -> UInt32 {
  let lerp_chan = fn(a : UInt32, b : UInt32) -> UInt32 {
    let v = a.to_double() * (1.0 - fx) + b.to_double() * fx
    clamp_f64(v.round(), 0.0, 255.0).to_int().reinterpret_as_uint()
  }
  let a0 = lerp_chan(c00 >> 24, c10 >> 24)
  let r0 = lerp_chan((c00 >> 16) & 0xFF, (c10 >> 16) & 0xFF)
  let g0 = lerp_chan((c00 >> 8) & 0xFF, (c10 >> 8) & 0xFF)
  let b0 = lerp_chan(c00 & 0xFF, c10 & 0xFF)
  let a1 = lerp_chan(c01 >> 24, c11 >> 24)
  let r1 = lerp_chan((c01 >> 16) & 0xFF, (c11 >> 16) & 0xFF)
  let g1 = lerp_chan((c01 >> 8) & 0xFF, (c11 >> 8) & 0xFF)
  let b1 = lerp_chan(c01 & 0xFF, c11 & 0xFF)
  let lerp2 = fn(u : UInt32, v : UInt32) -> UInt32 {
    let x = u.to_double() * (1.0 - fy) + v.to_double() * fy
    clamp_f64(x.round(), 0.0, 255.0).to_int().reinterpret_as_uint()
  }
  let a = lerp2(a0, a1)
  let r = lerp2(r0, r1)
  let g = lerp2(g0, g1)
  let b = lerp2(b0, b1)
  (a << 24) | (r << 16) | (g << 8) | b
}
