///|
/// ピクセルフォーマット。上流 `pixel/format.rs` に対応。
pub(all) enum PixelFormat {
  /// 32-bit premultiplied ARGB。u32 ワードで 0xAARRGGBB。
  /// メモリ上はリトルエンディアンのバイト列として保持する。
  Prgb32
  /// 32-bit XRGB。アルファは未使用 (通常 0xFF)。
  /// ストライドとメモリ幅は `Prgb32` と同じ。
  Xrgb32
  /// アルファのみ 8bit/ピクセル。合成は専用スカラ実装。
  A8
} derive(Eq, Debug)

///|
pub fn PixelFormat::bytes_per_pixel(self : PixelFormat) -> Int32 {
  match self {
    Prgb32 | Xrgb32 => 4
    A8 => 1
  }
}

///|
/// 画像の最大寸法 (ピクセル)。上流に明示的な上限はないが、
/// 過大確保を `ResourceLimit` で安全に失敗させるための移植側の制限。
/// 32767^2 * 4B ≒ 4GiB を個別に制限する max_buffer_bytes と併用する。
let max_image_dimension : Int32 = 32767

///|
/// バッファ全体の最大バイト数。Int (i32) のオーバーフローを避けるため
/// 1GiB に制限する。
let max_buffer_bytes : Int32 = 1 << 30

///|
/// ピクセルバッファを所有する画像。上流 `api/image.rs` の `Image` に対応。
///
/// バッファは `stride * height` バイトの所有配列で、
/// 4bpp 系のピクセルはリトルエンディアンの u32 として読み書きする
/// (ホストエンディアン非依存)。
pub struct Image {
  priv width : Int32
  priv height : Int32
  /// 1 行あたりのバイト数。
  priv stride : Int32
  priv format : PixelFormat
  priv data : FixedArray[Byte]
}

///|
/// 全要素 0 の画像を生成する。
///
/// 寸法・バッファ長を描画前に検証し、範囲外は `RadenError` を返す。
/// - `width`, `height`: 0..=32767。負値・上限超過は `InvalidInput` / `ResourceLimit`。
/// - 0 は許容し、空バッファの画像になる (上流と同じ)。
pub fn Image::new(
  width : Int32,
  height : Int32,
  format : PixelFormat,
) -> Image raise RadenError {
  if width < 0 || height < 0 {
    raise InvalidInput(
      "Image::new: negative dimensions (width=\{width}, height=\{height})",
    )
  }
  if width > max_image_dimension || height > max_image_dimension {
    raise ResourceLimit(
      "Image::new: dimension exceeds limit (width=\{width}, height=\{height}, max=\{max_image_dimension})",
    )
  }
  let stride = width * format.bytes_per_pixel()
  let total = stride.to_int64() * height.to_int64()
  if total > max_buffer_bytes.to_int64() {
    raise ResourceLimit(
      "Image::new: buffer too large (\{total} bytes > \{max_buffer_bytes})",
    )
  }
  {
    width,
    height,
    stride,
    format,
    data: FixedArray::make(total.to_int(), b'\x00'),
  }
}

///|
/// straight-alpha RGBA8 (row-major, w*h*4 バイト) から画像を生成する。
/// 各ピクセルを対象フォーマットへ変換する:
/// - `Prgb32` / `Xrgb32`: `premultiply_rgba` で premultiplied 化した LE u32
/// - `A8`: アルファバイトのみ
/// fixture の inline image と blit 入力の両方で使う。
pub fn Image::from_rgba8(
  width : Int32,
  height : Int32,
  format : PixelFormat,
  rgba8 : BytesView,
) -> Image raise RadenError {
  let img = Image::new(width, height, format)
  let expect = width * height * 4
  if rgba8.length() != expect {
    raise InvalidInput(
      "Image::from_rgba8: rgba8 length \{rgba8.length()} != \{expect}",
    )
  }
  let bpp = format.bytes_per_pixel()
  let npix = width * height
  for i in 0..<npix {
    let r = rgba8[i * 4].to_uint()
    let g = rgba8[i * 4 + 1].to_uint()
    let b = rgba8[i * 4 + 2].to_uint()
    let a = rgba8[i * 4 + 3].to_uint()
    let off = i * bpp
    if bpp == 1 {
      img.data[off] = a.to_byte()
    } else {
      img.write_u32(off, @pixel.premultiply_rgba(r, g, b, a))
    }
  }
  img
}

///|
pub fn Image::width(self : Image) -> Int32 {
  self.width
}

///|
pub fn Image::height(self : Image) -> Int32 {
  self.height
}

///|
/// 1 行あたりのバイト数。
pub fn Image::stride(self : Image) -> Int32 {
  self.stride
}

///|
pub fn Image::format(self : Image) -> PixelFormat {
  self.format
}

///|
/// バッファの読み取り専用ビューを返す。
/// `stride * height` バイト。4bpp 系はリトルエンディアンの u32 列。
pub fn Image::data(self : Image) -> BytesView {
  Bytes::from_array(self.data[:])[:]
}

///|
/// バッファを共有しない画像複製を返す。
/// blit の ソース == 宛先 エイリアス検出時のスナップショット用。
fn Image::snapshot(self : Image) -> Image {
  let n = self.data.length()
  let data = FixedArray::make(n, b'\x00')
  for i in 0..<n {
    data[i] = self.data[i]
  }
  Image::{
    width: self.width,
    height: self.height,
    stride: self.stride,
    format: self.format,
    data,
  }
}

///|
/// オフセット (バイト) からリトルエンディアンの u32 を読み取る。
/// 4bpp 系専用。
fn Image::read_u32(self : Image, offset : Int32) -> UInt32 {
  let d = self.data
  d[offset].to_uint() |
  (d[offset + 1].to_uint() << 8) |
  (d[offset + 2].to_uint() << 16) |
  (d[offset + 3].to_uint() << 24)
}

///|
/// オフセット (バイト) にリトルエンディアンの u32 を書き込む。
fn Image::write_u32(self : Image, offset : Int32, v : UInt32) -> Unit {
  let d = self.data
  d[offset] = v.to_byte()
  d[offset + 1] = (v >> 8).to_byte()
  d[offset + 2] = (v >> 16).to_byte()
  d[offset + 3] = (v >> 24).to_byte()
}

///|
pub extend PixelFormat with Eq::{not_equal, equal}

///|
pub extend PixelFormat with @debug.Debug::{to_repr}
