///|
/// 公開 library 導入済みの独立 consumer。
/// 内部 helper や非公開パッケージに依存せず公開 API だけで描画する。
fn main raise {
  let img = @raden.Image::new(64, 48, @raden.Prgb32)
  let runtime = @raden.PipelineRuntime::new()
  let ctx = @raden.Context::new(img, runtime)
  ctx.set_fill_style(@raden.Rgba32::rgb(255, 0, 0))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, 64.0, 48.0))
  let path = @raden.Path::new()
  path.move_to(8.0, 8.0)
  path.line_to(56.0, 8.0)
  path.line_to(32.0, 40.0)
  path.close()
  ctx.set_fill_style(@raden.Rgba32::rgb(0, 0, 255))
  ctx.fill_path(path)
  ctx.end()
  println("consumer render ok: \{img.width()}x\{img.height()}")
}
