///|
/// scene 出力の標準フォーマット。
/// headless CLI・ブラウザ・conformance 比較で共有する契約:
/// 「同じ scene・同じ size・同じ frame ならどのターゲットでも
///   同じ canonical バイト列が得られる」ことを保証する土台。

///|
/// Image を canonical な premultiplied RGBA8 バイト列へ変換する。
/// conformance/rust-oracle の canonical_bytes と同一の並び:
///   4bpp → LE u32 (0xAARRGGBB) を (R,G,B,A) へ分解
///   1bpp → alpha バイトを (0,0,0,A) へ分解
pub fn canonical_rgba8(img : @raden.Image) -> Bytes {
  let bpp = img.format().bytes_per_pixel()
  let w = img.width()
  let h = img.height()
  let stride = img.stride()
  let data = img.data()
  let out = FixedArray::make(w * h * 4, b'\x00')
  for y in 0..<h {
    for x in 0..<w {
      let off = y * stride + x * bpp
      let word = if bpp == 4 {
        data[off].to_uint() |
        (data[off + 1].to_uint() << 8) |
        (data[off + 2].to_uint() << 16) |
        (data[off + 3].to_uint() << 24)
      } else {
        data[off].to_uint() << 24
      }
      let o = (y * w + x) * 4
      out[o] = ((word >> 16) & 0xFF).to_byte()
      out[o + 1] = ((word >> 8) & 0xFF).to_byte()
      out[o + 2] = (word & 0xFF).to_byte()
      out[o + 3] = ((word >> 24) & 0xFF).to_byte()
    }
  }
  Bytes::from_array(out[:])
}

///|
/// scene を新規 Image に描画して返す。
/// canonical raw と host 側 BMP 出力の両方が同じ Image を共有できる。
pub fn render_to_image(
  name : SceneName,
  w : Int32,
  h : Int32,
  t : Double,
) -> @raden.Image raise @raden.RadenError {
  let img = @raden.Image::new(w, h, @raden.Prgb32)
  let ctx = @raden.Context::new(img, @raden.PipelineRuntime::new())
  render(ctx, name, w.to_double(), h.to_double(), t)
  img
}

///|
/// scene を新規 Image に描画し、canonical バイト列を返す。
/// 寸法が 0 以下なら `InvalidInput`。blocked scene は呼び出し側が
/// manifest に基づいて判定する (この関数は描画可能な scene のみ扱う)。
pub fn render_to_rgba8(
  name : SceneName,
  w : Int32,
  h : Int32,
  t : Double,
) -> Bytes raise @raden.RadenError {
  let img = render_to_image(name, w, h, t)
  canonical_rgba8(img)
}
