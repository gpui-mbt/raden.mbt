///|
/// 画像転送 (blit)。上流 `api/blit.rs` の移植。
/// `Context` のメソッドとして実装する。

///|
/// ソース画像を `dst` 矩形に Nearest 転送する。`src_rect` が `None` のときはソース全体。
///
/// 現在は `SrcOver` と `SrcCopy` のみ。ソースは `Prgb32` / `Xrgb32`、
/// 宛ては `Prgb32` / `Xrgb32` / `A8`。
/// 変換行列は現在の `matrix` を用いる (ユーザ空間の `dst` をデバイスへ写像)。
pub fn Context::blit_image_rect(
  self : Context,
  dst : Rect,
  src : Image,
  src_rect : Rect?,
) -> Unit raise RadenError {
  // 上流は assert で前提を強制する。移植版は InvalidInput エラーに分類する。
  match src.format() {
    Prgb32 | Xrgb32 => ()
    _ => raise InvalidInput("blit source must be Prgb32 or Xrgb32")
  }
  match self.comp_op {
    SrcOver | SrcCopy => ()
    _ => raise InvalidInput("blit supports only SrcOver and SrcCopy")
  }

  // 上流は借用規則により ソース == 宛先 の同時転送を表現できない。
  // MoonBit 側では同一 Image を渡せてしまい、書き込みが後続の
  // サンプル結果を汚染するため、エイリアス時はソースを
  // スナップショットしてから転送する。
  let src = if physical_equal(src, self.image) { src.snapshot() } else { src }

  let corners = [
    self.matrix.map_point(dst.x, dst.y),
    self.matrix.map_point(dst.x + dst.w, dst.y),
    self.matrix.map_point(dst.x + dst.w, dst.y + dst.h),
    self.matrix.map_point(dst.x, dst.y + dst.h),
  ]
  let mut min_x = @double.infinity
  let mut min_y = @double.infinity
  let mut max_x = @double.neg_infinity
  let mut max_y = @double.neg_infinity
  for c in corners {
    min_x = @cmp.minimum(min_x, c.0)
    min_y = @cmp.minimum(min_y, c.1)
    max_x = @cmp.maximum(max_x, c.0)
    max_y = @cmp.maximum(max_y, c.1)
  }
  let ix0 = @cmp.maximum(f64_to_i32_sat(min_x.floor()), self.clip_box.x0)
  let iy0 = @cmp.maximum(f64_to_i32_sat(min_y.floor()), self.clip_box.y0)
  let ix1 = @cmp.minimum(f64_to_i32_sat(max_x.ceil()), self.clip_box.x1)
  let iy1 = @cmp.minimum(f64_to_i32_sat(max_y.ceil()), self.clip_box.y1)
  if ix0 >= ix1 || iy0 >= iy1 {
    return
  }
  self.blit_image_rect_scoped(dst, src, src_rect, ix0, iy0, ix1, iy1)
}

///|
/// ソース画像全体を (x, y) に転送する。`blit_image_rect` のショートカット。
pub fn Context::blit_image_at(
  self : Context,
  x : Double,
  y : Double,
  src : Image,
) -> Unit raise RadenError {
  let r = Rect::new(x, y, src.width().to_double(), src.height().to_double())
  self.blit_image_rect(r, src, None)
}

///|
/// デバイス座標 (ix, iy) をユーザ空間へ写し、
/// dst 矩形内を src 矩形へ写像してサンプルする Nearest 転送。
fn Context::blit_image_rect_scoped(
  self : Context,
  dst_rect_user : Rect,
  src : Image,
  src_rect : Rect?,
  clip_x0 : Int32,
  clip_y0 : Int32,
  clip_x1 : Int32,
  clip_y1 : Int32,
) -> Unit {
  let sr = match src_rect {
    Some(r) => r
    None =>
      Rect::new(0.0, 0.0, src.width().to_double(), src.height().to_double())
  }

  if dst_rect_user.w <= 0.0 ||
    dst_rect_user.h <= 0.0 ||
    sr.w <= 0.0 ||
    sr.h <= 0.0 {
    return
  }

  guard self.matrix.invert() is Some(inv) else { return }

  let dst_stride = self.image.stride()
  let dst_fmt = self.image.format()
  let dst_bpp = dst_fmt.bytes_per_pixel()

  let src_stride = src.stride()
  let sw = src.width()
  let sh = src.height()
  let dst_image = self.image
  let comp_op = self.comp_op

  for iy in clip_y0..<clip_y1 {
    for ix in clip_x0..<clip_x1 {
      let (ux, uy) = inv.map_point(ix.to_double() + 0.5, iy.to_double() + 0.5)
      if ux < dst_rect_user.x ||
        ux >= dst_rect_user.x + dst_rect_user.w ||
        uy < dst_rect_user.y ||
        uy >= dst_rect_user.y + dst_rect_user.h {
        continue
      }
      let tu = sr.x + (ux - dst_rect_user.x) / dst_rect_user.w * sr.w
      let tv = sr.y + (uy - dst_rect_user.y) / dst_rect_user.h * sr.h
      let sx = f64_to_i32_sat(tu.floor())
      let sy = f64_to_i32_sat(tv.floor())
      if sx < 0 || sy < 0 || sx >= sw || sy >= sh {
        continue
      }
      let sp = src.read_u32(sy * src_stride + sx * 4)
      let off = iy * dst_stride + ix * dst_bpp
      match dst_fmt {
        Prgb32 | Xrgb32 =>
          match comp_op {
            SrcCopy => dst_image.write_u32(off, sp)
            SrcOver =>
              dst_image.write_u32(
                off,
                @pixel.comp_src_over(dst_image.read_u32(off), sp),
              )
            _ => ()
          }
        A8 =>
          match comp_op {
            SrcCopy => dst_image.data[off] = (sp >> 24).to_byte()
            SrcOver => {
              let sa = (sp >> 24) & 0xFF
              if sa == 0 {
                continue
              }
              let d = dst_image.data[off].to_uint()
              let out = sa + d * (255 - sa) / 255
              dst_image.data[off] = @cmp.minimum(out, 255).to_byte()
            }
            _ => ()
          }
      }
    }
  }
}
