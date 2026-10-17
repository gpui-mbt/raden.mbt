///|
/// BMP host writer の検証。
/// 上流 `src/codec/bmp.rs` と同じ top-down 32bpp / BI_BITFIELDS 形式か、
/// ピクセルバイトが Prgb32 の LE バイト列 (B,G,R,A) のままか確認する。

///|
fn bmp_u16(b : Bytes, off : Int32) -> Int32 {
  b[off].to_int() | (b[off + 1].to_int() << 8)
}

///|
fn bmp_u32(b : Bytes, off : Int32) -> Int64 {
  b[off].to_int64() |
  (b[off + 1].to_int64() << 8) |
  (b[off + 2].to_int64() << 16) |
  (b[off + 3].to_int64() << 24)
}

///|
test "BMP: header と top-down ピクセル" {
  let img = @raden.Image::new(2, 2, @raden.Prgb32) catch {
    _ => fail("@raden.Image::new")
  }
  let ctx = @raden.Context::new(img, @raden.PipelineRuntime::new())
  ctx.set_comp_op(@raden.SrcCopy)
  ctx.set_fill_style(@raden.Rgba32::new(0x11, 0x22, 0x33, 0xFF))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, 2.0, 2.0)) catch {
    _ => fail("fill_rect")
  }
  let bmp = encode_bmp(img) catch { e => fail("encode_bmp: \{e.to_string()}") }
  // 14 + 40 + 12 + 2*2*4 = 82 bytes
  inspect(bmp[0].to_int(), content="66") // 'B'
  inspect(bmp[1].to_int(), content="77") // 'M'
  inspect(bmp_u32(bmp, 2), content="82")
  inspect(bmp_u32(bmp, 10), content="66")
  inspect(bmp_u32(bmp, 14), content="40")
  inspect(bmp_u32(bmp, 18), content="2") // width
  inspect(bmp_u32(bmp, 22), content="4294967294") // height = -2
  inspect(bmp_u16(bmp, 26), content="1") // planes
  inspect(bmp_u16(bmp, 28), content="32") // bpp
  inspect(bmp_u32(bmp, 30), content="3") // BI_BITFIELDS
  inspect(bmp_u32(bmp, 34), content="16") // pixel data size
  inspect(bmp_u32(bmp, 54), content="16711680") // R mask
  inspect(bmp_u32(bmp, 58), content="65280") // G mask
  inspect(bmp_u32(bmp, 62), content="255") // B mask
  // Prgb32 の LE バイト列 (B,G,R,A) がそのまま並ぶ。
  inspect(bmp[66].to_int(), content="51")
  inspect(bmp[67].to_int(), content="34")
  inspect(bmp[68].to_int(), content="17")
  inspect(bmp[69].to_int(), content="255")
  inspect(bmp.length(), content="82")
}

///|
test "BMP: A8 は UnsupportedFeature" {
  let img = @raden.Image::new(2, 2, @raden.A8) catch {
    _ => fail("@raden.Image::new")
  }
  try encode_bmp(img) catch {
    e => inspect(e is @raden.UnsupportedFeature(_), content="true")
  } noraise {
    _ => fail("expected UnsupportedFeature for A8 BMP")
  }
}
