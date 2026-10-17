///|
/// 上流 `examples/raden_player.rs` の scene 部分 (表示 host を除く)。
///
/// shape は `examples/scenes` の animation と共通で、その上に
/// 経過時間・情報・frame 番号・FPS を font で重ねる。
/// 上流は macOS の Helvetica.ttc と wall clock FPS を使うが、
/// 決定性と CI 再現性のため、ここでは vendored SourceSans3 と
/// target FPS 固定の actual FPS を使う (既知差分 #12/#13)。

///|
/// 小数 1 桁固定の FPS 表記。上流の `{:.1}` に合わせる。
fn format_fps(v : Double) -> String {
  let tenths = (v * 10.0 + 0.5).to_int()
  "\{tenths / 10}.\{tenths % 10}"
}

///|
/// raden_player の 1 frame を描く。
/// `t` は秒、`frame_number` は 0 始まり、`target_fps` は表示用の固定値。
/// `actual_fps` は host が決める (headless では target と同値にして決定化する)。
pub fn render(
  ctx : @raden.Context,
  w : Double,
  h : Double,
  t : Double,
  font_large : @font.Font,
  font_small : @font.Font,
  frame_number : Int64,
  target_fps : Int32,
  actual_fps : Double,
) -> Unit raise @raden.RadenError {
  @scenes.animation_frame(ctx, t, w, h)

  let elapsed_ms = (t * 1000.0).to_int64()
  let time_text = "\{elapsed_ms.to_string().pad_start(8, '0')} ms"
  let text_x = w * 0.5 - 200.0
  let text_y = h * 0.85

  // 影
  ctx.set_fill_style(@raden.Rgba32::new(0, 0, 0, 200))
  @font.fill_text(ctx, text_x + 3.0, text_y + 3.0, font_large, time_text)
  // 本体
  ctx.set_fill_style(@raden.Rgba32::new(255, 255, 255, 255))
  @font.fill_text(ctx, text_x, text_y, font_large, time_text)

  // 情報表示
  ctx.set_fill_style(@raden.Rgba32::new(255, 255, 255, 200))
  let info_text = "\{w.to_int()}x\{h.to_int()} | \{target_fps} FPS | RAW BGRA"
  @font.fill_text(ctx, 30.0, 50.0, font_small, info_text)

  // フレーム番号
  ctx.set_fill_style(@raden.Rgba32::new(200, 200, 200, 255))
  let frame_text = "Frame: \{frame_number.to_string().pad_start(6, '0')}"
  @font.fill_text(ctx, 30.0, 95.0, font_small, frame_text)

  // 実際の FPS (緑)
  ctx.set_fill_style(@raden.Rgba32::new(150, 255, 150, 255))
  let fps_text = "FPS: \{format_fps(actual_fps)}"
  @font.fill_text(ctx, 30.0, 140.0, font_small, fps_text)
}
