///|
/// BMP 書き出し (host 層)。
///
/// 上流 `src/codec/bmp.rs` と同じ形式で書き出す:
/// - BITMAPINFOHEADER + BI_BITFIELDS
/// - negative height による top-down 格納 (行反転なし)
/// - 32bpp、R=0x00FF0000 / G=0x0000FF00 / B=0x000000FF
/// - Prgb32 の LE バイト列 (B,G,R,A) をそのままコピーする
///
/// 描画コアへ BMP 依存を持ち込まないため、このファイルは
/// raden-demo (native host) パッケージだけに置く。

///|
fn put_u16_le(buf : FixedArray[Byte], off : Int32, v : Int32) -> Unit {
  buf[off] = (v & 0xFF).to_byte()
  buf[off + 1] = ((v >> 8) & 0xFF).to_byte()
}

///|
fn put_u32_le(buf : FixedArray[Byte], off : Int32, v : Int64) -> Unit {
  let u = v & 4294967295L
  buf[off] = (u & 255L).to_int().to_byte()
  buf[off + 1] = ((u >> 8) & 255L).to_int().to_byte()
  buf[off + 2] = ((u >> 16) & 255L).to_int().to_byte()
  buf[off + 3] = ((u >> 24) & 255L).to_int().to_byte()
}

///|
/// 4bpp 画像を top-down 32bit BMP のバイト列へ変換する。
/// A8 など 4bpp 以外は `UnsupportedFeature` で失敗する。
pub fn encode_bmp(img : @raden.Image) -> Bytes raise @raden.RadenError {
  if img.format().bytes_per_pixel() != 4 {
    raise @raden.RadenError::UnsupportedFeature(
      "bmp: only 32-bit (Prgb32/Xrgb32) images are supported",
    )
  }
  let width = img.width()
  let height = img.height()
  let stride = img.stride()
  if width <= 0 || height <= 0 {
    raise @raden.RadenError::InvalidInput(
      "bmp: empty image (width=\{width}, height=\{height})",
    )
  }
  let pixel_size = stride * height
  let pixel_offset = 14 + 40 + 12
  let total = pixel_offset + pixel_size
  let out = FixedArray::make(total, b'\x00')

  // BITMAPFILEHEADER (14 bytes)
  out[0] = b'B'
  out[1] = b'M'
  put_u32_le(out, 2, total.to_int64())
  put_u16_le(out, 6, 0)
  put_u16_le(out, 8, 0)
  put_u32_le(out, 10, pixel_offset.to_int64())

  // BITMAPINFOHEADER (40 bytes)
  put_u32_le(out, 14, 40L)
  put_u32_le(out, 18, width.to_int64())
  put_u32_le(out, 22, -height.to_int64()) // top-down
  put_u16_le(out, 26, 1) // planes
  put_u16_le(out, 28, 32) // bpp
  put_u32_le(out, 30, 3L) // BI_BITFIELDS
  put_u32_le(out, 34, pixel_size.to_int64())
  put_u32_le(out, 38, 2835L) // 72 DPI
  put_u32_le(out, 42, 2835L)
  put_u32_le(out, 46, 0L)
  put_u32_le(out, 50, 0L)

  // Color masks (12 bytes)
  put_u32_le(out, 54, 16711680L) // R = 0x00FF0000
  put_u32_le(out, 58, 65280L) // G = 0x0000FF00
  put_u32_le(out, 62, 255L) // B = 0x000000FF

  // Pixel data: Prgb32 は LE で B,G,R,A の順に並んでいる。
  let data = img.data()
  for i in 0..<pixel_size {
    out[pixel_offset + i] = data[i]
  }
  Bytes::from_array(out[:])
}
