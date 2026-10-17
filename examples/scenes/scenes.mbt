///|
/// 上流 examples の scene 部分の移植 (表示 host を除く)。
/// 描画命令と定数は conformance/rust-oracle/src/scenes.rs と一致させ、
/// これは上流 examples/*.rs の scene 部分をそのまま転記したものである。
/// 壁時計・乱数・ファイルパス・ウィンドウイベントには一切依存しない。
/// 時間依存の scene は呼び出し側が `t` (秒) を明示的に与える。

///|
/// サポートする scene 名。
pub(all) enum SceneName {
  BasicDrawing
  GradientDrawing
  StrokeDrawing
  BlitClipPatternPaths
  Animation
} derive(Eq, Debug)

///|
pub extend SceneName with Eq::{not_equal, equal}

///|
pub extend SceneName with @debug.Debug::{to_repr}

///|
/// scene 名の文字列をパースする。manifest / CLI / fixture で共用する。
pub fn SceneName::parse(s : String) -> SceneName raise @raden.RadenError {
  match s {
    "basic_drawing" => BasicDrawing
    "gradient_drawing" => GradientDrawing
    "stroke_drawing" => StrokeDrawing
    "blit_clip_pattern_paths" => BlitClipPatternPaths
    "animation" => Animation
    other => raise @raden.RadenError::InvalidInput("unknown scene: \{other}")
  }
}

///|
/// scene を Context 上に描画する。
/// `t` は時間依存 scene のみ使用する (animation)。それ以外では無視する。
/// `w`/`h` は対象画像の寸法 (上流は 1280x720 前提のレイアウトが多い)。
pub fn render(
  ctx : @raden.Context,
  name : SceneName,
  w : Double,
  h : Double,
  t : Double,
) -> Unit raise @raden.RadenError {
  match name {
    BasicDrawing => basic_drawing(ctx, w, h)
    GradientDrawing => gradient_drawing(ctx, w, h)
    StrokeDrawing => stroke_drawing(ctx, w, h)
    BlitClipPatternPaths => blit_clip_pattern_paths(ctx, w, h)
    Animation => animation_frame(ctx, t, w, h)
  }
}

///|
/// frame index から animation の時刻を決定する。
/// 上流では `t = frame / fps` (実時間ではなく明示的)。
pub fn animation_t(frame : Int64, fps : Int64) -> Double {
  frame.to_double() / fps.to_double()
}

// =============================================================================
// basic_drawing.rs (上流定数をそのまま使用)
// =============================================================================

///|
fn basic_drawing(
  ctx : @raden.Context,
  w : Double,
  h : Double,
) -> Unit raise @raden.RadenError {
  // 青背景 (@raden.SrcCopy で全面上書き)
  ctx.set_comp_op(@raden.SrcCopy)
  ctx.set_fill_style(@raden.Rgba32::new(0x20, 0x20, 0x60, 0xFF))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, w, h))

  // 半透明矩形を重ねる (@raden.SrcOver)
  ctx.set_comp_op(@raden.SrcOver)

  // 不透明赤矩形
  ctx.set_fill_style(@raden.Rgba32::new(0xFF, 0x00, 0x00, 0xFF))
  ctx.fill_rect(@raden.Rect::new(10.0, 10.0, 400.0, 300.0))

  // 半透明緑矩形
  ctx.set_fill_style(@raden.Rgba32::new(0x00, 0xFF, 0x00, 0x80))
  ctx.fill_rect(@raden.Rect::new(200.0, 150.0, 400.0, 300.0))

  // 半透明青矩形
  ctx.set_fill_style(@raden.Rgba32::new(0x00, 0x00, 0xFF, 0x80))
  ctx.fill_rect(@raden.Rect::new(500.0, 300.0, 400.0, 300.0))
}

// =============================================================================
// gradient_drawing.rs (上流定数をそのまま使用)
// =============================================================================

///|
fn gradient_drawing(
  ctx : @raden.Context,
  w : Double,
  h : Double,
) -> Unit raise @raden.RadenError {
  // 暗い背景
  ctx.set_comp_op(@raden.SrcCopy)
  ctx.set_fill_style(@raden.Rgba32::new(0x1A, 0x1A, 0x2E, 0xFF))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, w, h))
  ctx.set_comp_op(@raden.SrcOver)

  // 上段: Linear グラデーション (@raden.Pad / @raden.Repeat / @raden.Reflect)
  let cell_w = 360.0
  let cell_h = 200.0
  let margin = 20.0
  let base_y = 30.0
  let extend_modes : Array[@raden.ExtendMode] = [
    @raden.Pad,
    @raden.Repeat,
    @raden.Reflect,
  ]
  for i, mode in extend_modes {
    let x = margin + (cell_w + margin) * i.to_double()
    let y = base_y
    let gx0 = x + cell_w * 0.33
    let gx1 = x + cell_w * 0.67
    let grad = @raden.Gradient::new_linear(gx0, y, gx1, y)
    grad.add_stop(0.0, @raden.Rgba32::new(0x00, 0x80, 0xFF, 0xFF)) |> ignore
    grad.add_stop(0.5, @raden.Rgba32::new(0xFF, 0xFF, 0x00, 0xFF)) |> ignore
    grad.add_stop(1.0, @raden.Rgba32::new(0xFF, 0x20, 0x60, 0xFF)) |> ignore
    grad.set_extend_mode(mode) |> ignore
    ctx.set_fill_style_gradient(grad)
    ctx.fill_rect(@raden.Rect::new(x, y, cell_w, cell_h))
  }

  // 下段左: Radial グラデーション
  let radial_x = margin
  let radial_y = base_y + cell_h + margin
  let radial_w = (w - margin * 3.0) / 2.0
  let radial_h = h - radial_y - margin
  let cx = radial_x + radial_w * 0.5
  let cy = radial_y + radial_h * 0.5
  let r = @cmp.minimum(radial_w, radial_h) * 0.45
  let fx = cx - r * 0.3
  let fy = cy - r * 0.2
  let radial = @raden.Gradient::new_radial(cx, cy, fx, fy, 0.0, r)
  radial.add_stop(0.0, @raden.Rgba32::new(0xFF, 0xFF, 0xFF, 0xFF)) |> ignore
  radial.add_stop(0.3, @raden.Rgba32::new(0xFF, 0xA0, 0x00, 0xFF)) |> ignore
  radial.add_stop(0.7, @raden.Rgba32::new(0xFF, 0x20, 0x60, 0xFF)) |> ignore
  radial.add_stop(1.0, @raden.Rgba32::new(0x20, 0x00, 0x40, 0xFF)) |> ignore
  ctx.set_fill_style_gradient(radial)
  ctx.fill_rect(@raden.Rect::new(radial_x, radial_y, radial_w, radial_h))

  // 下段右: Conic グラデーション
  let conic_x = radial_x + radial_w + margin
  let conic_y = radial_y
  let conic_w = radial_w
  let conic_h = radial_h
  let ccx = conic_x + conic_w * 0.5
  let ccy = conic_y + conic_h * 0.5
  let conic = @raden.Gradient::new_conic(ccx, ccy, 0.0)
  conic.add_stop(0.0, @raden.Rgba32::new(0xFF, 0x00, 0x00, 0xFF)) |> ignore
  conic.add_stop(0.17, @raden.Rgba32::new(0xFF, 0xFF, 0x00, 0xFF)) |> ignore
  conic.add_stop(0.33, @raden.Rgba32::new(0x00, 0xFF, 0x00, 0xFF)) |> ignore
  conic.add_stop(0.50, @raden.Rgba32::new(0x00, 0xFF, 0xFF, 0xFF)) |> ignore
  conic.add_stop(0.67, @raden.Rgba32::new(0x00, 0x00, 0xFF, 0xFF)) |> ignore
  conic.add_stop(0.83, @raden.Rgba32::new(0xFF, 0x00, 0xFF, 0xFF)) |> ignore
  conic.add_stop(1.0, @raden.Rgba32::new(0xFF, 0x00, 0x00, 0xFF)) |> ignore
  ctx.set_fill_style_gradient(conic)
  ctx.fill_rect(@raden.Rect::new(conic_x, conic_y, conic_w, conic_h))
}

// =============================================================================
// stroke_drawing.rs (上流定数をそのまま使用)
// =============================================================================

///|
fn stroke_drawing(
  ctx : @raden.Context,
  w : Double,
  h : Double,
) -> Unit raise @raden.RadenError {
  // 暗い背景
  ctx.set_comp_op(@raden.SrcCopy)
  ctx.set_fill_style(@raden.Rgba32::new(0x1A, 0x1A, 0x2E, 0xFF))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, w, h))
  ctx.set_comp_op(@raden.SrcOver)

  // --- 線分のストローク (異なるキャップ) ---
  ctx.save()
  ctx.set_stroke_style(@raden.Rgba32::new(0xFF, 0x60, 0x60, 0xFF))
  ctx.set_stroke_width(8.0)
  ctx.set_stroke_cap(@raden.Butt)
  ctx.stroke_line(@raden.Line::new(50.0, 80.0, 350.0, 80.0))
  ctx.set_stroke_style(@raden.Rgba32::new(0x60, 0xFF, 0x60, 0xFF))
  ctx.set_stroke_cap(@raden.Square)
  ctx.stroke_line(@raden.Line::new(50.0, 120.0, 350.0, 120.0))
  ctx.set_stroke_style(@raden.Rgba32::new(0x60, 0x60, 0xFF, 0xFF))
  ctx.set_stroke_cap(@raden.Round)
  ctx.stroke_line(@raden.Line::new(50.0, 160.0, 350.0, 160.0))
  ctx.restore()

  // --- 矩形のストローク (異なるジョイン) ---
  ctx.save()
  ctx.set_stroke_style(@raden.Rgba32::new(0xFF, 0xA0, 0x00, 0xFF))
  ctx.set_stroke_width(6.0)
  ctx.set_stroke_cap(@raden.Butt)
  ctx.set_stroke_join(@raden.Bevel)
  ctx.stroke_rect(@raden.Rect::new(50.0, 220.0, 200.0, 150.0))
  ctx.set_stroke_style(@raden.Rgba32::new(0x00, 0xFF, 0xA0, 0xFF))
  ctx.set_stroke_join(@raden.MiterBevel)
  ctx.stroke_rect(@raden.Rect::new(300.0, 220.0, 200.0, 150.0))
  ctx.set_stroke_style(@raden.Rgba32::new(0xA0, 0x00, 0xFF, 0xFF))
  ctx.set_stroke_join(@raden.Round)
  ctx.stroke_rect(@raden.Rect::new(550.0, 220.0, 200.0, 150.0))
  ctx.restore()

  // --- 円のストローク ---
  ctx.save()
  ctx.set_stroke_style(@raden.Rgba32::new(0xFF, 0xFF, 0x00, 0xC0))
  ctx.set_stroke_width(4.0)
  ctx.stroke_circle(@raden.Circle::new(900.0, 300.0, 80.0))
  ctx.restore()

  // --- 複雑なパスのストローク ---
  ctx.save()
  ctx.set_stroke_style(@raden.Rgba32::new(0xFF, 0x80, 0xC0, 0xFF))
  ctx.set_stroke_width(5.0)
  ctx.set_stroke_cap(@raden.Round)
  ctx.set_stroke_join(@raden.Round)
  let triangle = @raden.Path::new()
  triangle.move_to(150.0, 450.0)
  triangle.line_to(300.0, 600.0)
  triangle.line_to(0.0, 600.0)
  triangle.close()
  ctx.stroke_path(triangle)
  ctx.set_stroke_style(@raden.Rgba32::new(0xFF, 0xD7, 0x00, 0xFF))
  ctx.set_stroke_width(3.0)
  ctx.set_stroke_cap(@raden.Round)
  ctx.set_stroke_join(@raden.MiterBevel)
  ctx.set_stroke_miter_limit(10.0)
  let star = @raden.Path::new()
  let scx = 500.0
  let scy = 550.0
  let outer_r = 80.0
  let inner_r = 35.0
  for i in 0..<10 {
    let angle = @math.PI * 2.0 * i.to_double() / 10.0 - @math.PI / 2.0
    let r = if i % 2 == 0 { outer_r } else { inner_r }
    let x = scx + @math.cos(angle) * r
    let y = scy + @math.sin(angle) * r
    if i == 0 {
      star.move_to(x, y)
    } else {
      star.line_to(x, y)
    }
  }
  star.close()
  ctx.stroke_path(star)
  ctx.restore()

  // --- 異なる幅の線分 ---
  ctx.save()
  ctx.set_stroke_cap(@raden.Round)
  ctx.set_stroke_join(@raden.Round)
  let widths : Array[Double] = [1.0, 2.0, 4.0, 8.0, 12.0]
  for i, sw in widths {
    let y = 480.0 + i.to_double() * 30.0
    let brightness = 0x80 + i * 0x18
    ctx.set_stroke_style(
      @raden.Rgba32::new(
        brightness.reinterpret_as_uint(),
        brightness.reinterpret_as_uint(),
        0xFF,
        0xFF,
      ),
    )
    ctx.set_stroke_width(sw)
    ctx.stroke_line(@raden.Line::new(700.0, y, 1000.0, y))
  }
  ctx.restore()

  // --- 半透明ストローク ---
  ctx.save()
  ctx.set_stroke_style(@raden.Rgba32::new(0xFF, 0x00, 0x00, 0x60))
  ctx.set_stroke_width(20.0)
  ctx.set_stroke_cap(@raden.Round)
  ctx.stroke_circle(@raden.Circle::new(1100.0, 550.0, 100.0))
  ctx.set_stroke_style(@raden.Rgba32::new(0x00, 0xFF, 0x00, 0x60))
  ctx.stroke_circle(@raden.Circle::new(1150.0, 500.0, 100.0))
  ctx.restore()
}

// =============================================================================
// blit_clip_pattern_paths.rs (上流定数・タイル生成をそのまま使用)
// =============================================================================

///|
/// チェッカー模様の `Prgb32` 画像 (blit 用)。
/// 不透明タイルのため premultiply は恒等。straight-alpha RGBA8 で構築する。
fn checkerboard_tile(size : Int32) -> @raden.Image raise @raden.RadenError {
  let c0 : Bytes = [0xC8, 0x50, 0x50, 0xFF]
  let c1 : Bytes = [0x50, 0xC8, 0xC8, 0xFF]
  let cell = 8
  let data : Array[Byte] = []
  for y in 0..<size {
    for x in 0..<size {
      let ix = x / cell
      let iy = y / cell
      let px = if (ix + iy) % 2 == 0 { c0 } else { c1 }
      for i in 0..<4 {
        data.push(px[i])
      }
    }
  }
  @raden.Image::from_rgba8(
    size,
    size,
    @raden.Prgb32,
    Bytes::from_array(data[:])[:],
  )
}

///|
/// 横ストライプの `Prgb32` 画像 (パターン塗り専用)。
fn horizontal_stripe_tile(size : Int32) -> @raden.Image raise @raden.RadenError {
  let c0 : Bytes = [0xFF, 0xA0, 0x20, 0xFF]
  let c1 : Bytes = [0x20, 0x40, 0xE8, 0xFF]
  let band = 6
  let data : Array[Byte] = []
  for y in 0..<size {
    for _x in 0..<size {
      let px = if y / band % 2 == 0 { c0 } else { c1 }
      for i in 0..<4 {
        data.push(px[i])
      }
    }
  }
  @raden.Image::from_rgba8(
    size,
    size,
    @raden.Prgb32,
    Bytes::from_array(data[:])[:],
  )
}

///|
fn blit_clip_pattern_paths(
  ctx : @raden.Context,
  w : Double,
  h : Double,
) -> Unit raise @raden.RadenError {
  let tile = checkerboard_tile(56)
  let stripe = horizontal_stripe_tile(48)
  let clip_window = @raden.Rect::new(420.0, 80.0, 280.0, 220.0)

  // 背景
  ctx.set_comp_op(@raden.SrcCopy)
  ctx.set_fill_style(@raden.Rgba32::new(0x12, 0x14, 0x22, 0xFF))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, w, h))
  ctx.set_comp_op(@raden.SrcOver)

  // --- blit: 行列で回転した転送 (@raden.Nearest) ---
  let half = tile.width().to_double() * 0.5
  ctx.save()
  ctx.post_translate(220.0, 180.0)
  ctx.post_rotate(0.85)
  ctx.blit_image_at(-half, -half, tile)
  ctx.restore()

  // --- 矩形クリップ: 円を描くが窓の外は描かれない ---
  ctx.save()
  ctx.clip_to_rect(clip_window)
  ctx.set_fill_style(@raden.Rgba32::new(0xFF, 0xDD, 0x20, 0xFF))
  ctx.fill_circle(@raden.Circle::new(330.0, 190.0, 175.0))
  ctx.restore()

  // --- パターン: ストライプ画像 + @raden.Bilinear + スケール ---
  let pat = @raden.Pattern::from_image(stripe)
  pat.set_filter(@raden.Bilinear) |> ignore
  pat.set_transform(@raden.Matrix2D::scaling(1.4, 1.4)) |> ignore
  ctx.set_fill_style_pattern(pat)
  ctx.fill_rect(@raden.Rect::new(80.0, 380.0, 320.0, 240.0))
  ctx.set_fill_style(@raden.Rgba32::new(0xFF, 0xFF, 0xFF, 0xFF))

  // --- 拡張パス + せん断した座標系 ---
  ctx.save()
  ctx.post_translate(520.0, 360.0)
  ctx.post_skew(0.12, 0.0)
  let p = @raden.Path::new()
  // smooth_quad_to: 直前の quad_to が必要
  p.move_to(0.0, 0.0)
  p.quad_to(40.0, -60.0, 80.0, 0.0)
  p.smooth_quad_to(120.0, 0.0)
  // smooth_cubic_to: 直前の cubic_to が必要
  p.move_to(0.0, 80.0)
  p.cubic_to(10.0, 40.0, 50.0, 40.0, 60.0, 80.0)
  p.smooth_cubic_to(110.0, 120.0, 160.0, 80.0)
  // 円錐曲線 (有理二次)
  p.move_to(180.0, 20.0)
  p.conic_to(220.0, 60.0, 260.0, 20.0, 0.85)
  // 楕円弧 (arc_to)
  p.move_to(300.0, 80.0)
  p.arc_to(340.0, 50.0, 35.0, 28.0, 0.0, @math.PI * 1.2, true)
  ctx.set_fill_style(@raden.Rgba32::new(0x66, 0xAA, 0xFF, 0xD0))
  ctx.set_stroke_style(@raden.Rgba32::new(0xFF, 0xFF, 0xFF, 0xFF))
  ctx.set_stroke_width(2.0)
  ctx.set_stroke_cap(@raden.Round)
  ctx.set_stroke_join(@raden.Round)
  ctx.fill_path(p)
  ctx.stroke_path(p)
  ctx.restore()

  // --- もう一枚 blit (@raden.SrcCopy で矩形を上書き。チェッカーを粗く拡大) ---
  ctx.save()
  ctx.set_comp_op(@raden.SrcCopy)
  ctx.blit_image_rect(
    @raden.Rect::new(900.0, 420.0, 160.0, 120.0),
    tile,
    Some(
      @raden.Rect::new(
        0.0,
        0.0,
        tile.width().to_double(),
        tile.height().to_double(),
      ),
    ),
  )
  ctx.restore()
}

// =============================================================================
// animation.rs render_frame (上流をそのまま転記)
// =============================================================================

///|
const NUM_WAVES : Int32 = 5

///|
const NUM_BALLS : Int32 = 8

///|
const NUM_SHAPES : Int32 = 6

///|
/// HSV を RGB に変換する (h: 0-360, s: 0-1, v: 0-1)。
fn hsv_to_rgb(h : Double, s : Double, v : Double) -> (Byte, Byte, Byte) {
  let c = v * s
  let x = c * (1.0 - (h / 60.0 % 2.0 - 1.0).abs())
  let m = v - c
  let (r, g, b) = if h < 60.0 {
    (c, x, 0.0)
  } else if h < 120.0 {
    (x, c, 0.0)
  } else if h < 180.0 {
    (0.0, c, x)
  } else if h < 240.0 {
    (0.0, x, c)
  } else if h < 300.0 {
    (x, 0.0, c)
  } else {
    (c, 0.0, x)
  }
  (
    ((r + m) * 255.0).to_int().to_byte(),
    ((g + m) * 255.0).to_int().to_byte(),
    ((b + m) * 255.0).to_int().to_byte(),
  )
}

///|
/// 上流 animation/raden_player 共通の shape scene。
/// raden_player はこの後にフォントのオーバーレイを描く。
pub fn animation_frame(
  ctx : @raden.Context,
  t : Double,
  w : Double,
  h : Double,
) -> Unit raise @raden.RadenError {
  // --- 背景: HSV で色相がゆっくり変化する暗い背景 (@raden.SrcCopy) ---
  ctx.set_comp_op(@raden.SrcCopy)
  let bg_hue = t * 20.0 % 360.0
  let (br, bg, bb) = hsv_to_rgb(bg_hue, 0.3, 0.15)
  ctx.set_fill_style(
    @raden.Rgba32::new(br.to_uint(), bg.to_uint(), bb.to_uint(), 0xFF),
  )
  ctx.fill_all()
  ctx.set_comp_op(@raden.SrcOver)

  // --- ウェーブパターン: 横方向に並ぶ円が sin 波で上下に動く ---
  for wave_idx in 0..<NUM_WAVES {
    let wi = wave_idx.to_double()
    let wave_offset = wi * 0.5
    let wave_amplitude = 50.0 + wi * 20.0
    let wave_freq = 0.008 + wi * 0.002
    let wave_speed = 2.0 + wi * 0.3
    let wave_y_base = h * 0.3 + wi * 80.0
    let wave_hue = (t * 60.0 + wi * 50.0) % 360.0
    let (wr, wg, wb) = hsv_to_rgb(wave_hue, 0.8, 0.9)
    ctx.set_fill_style(
      @raden.Rgba32::new(wr.to_uint(), wg.to_uint(), wb.to_uint(), 150),
    )
    let mut x = 0.0
    while x < w {
      let y = wave_y_base +
        wave_amplitude * @math.sin(wave_freq * x + t * wave_speed + wave_offset)
      let radius = 8.0 + 4.0 * @math.sin(t * 3.0 + x * 0.01)
      ctx.fill_circle(@raden.Circle::new(x, y, radius))
      x += 20.0
    }
  }

  // --- バウンドする円: リサージュ曲線風に動く複数の半透明円 ---
  for ball_idx in 0..<NUM_BALLS {
    let bi = ball_idx.to_double()
    let freq_x = 0.5 + bi * 0.15
    let freq_y = 0.7 + bi * 0.12
    let phase_x = bi * @math.PI / 4.0
    let phase_y = bi * @math.PI / 3.0
    let bx = w * 0.5 + w * 0.35 * @math.sin(t * freq_x + phase_x)
    let by = h * 0.5 + h * 0.3 * @math.sin(t * freq_y + phase_y)
    let ball_radius = 30.0 + 15.0 * @math.sin(t * 4.0 + bi)
    let ball_hue = (bi * 45.0 + t * 100.0) % 360.0
    let (cr, cg, cb) = hsv_to_rgb(ball_hue, 1.0, 1.0)
    ctx.set_fill_style(
      @raden.Rgba32::new(cr.to_uint(), cg.to_uint(), cb.to_uint(), 200),
    )
    ctx.fill_circle(@raden.Circle::new(bx, by, ball_radius))

    // 光沢効果 (小さい白い円、左上寄りに配置)
    ctx.save()
    let hl_radius = ball_radius * 0.3
    ctx.set_fill_style(@raden.Rgba32::new(255, 255, 255, 100))
    ctx.fill_circle(
      @raden.Circle::new(
        bx - ball_radius * 0.3,
        by - ball_radius * 0.3,
        hl_radius,
      ),
    )
    ctx.restore()
  }

  // --- 回転する円群: 中央周囲を周回する円 ---
  let center_x = w * 0.5
  let center_y = h * 0.5
  for shape_idx in 0..<NUM_SHAPES {
    let si = shape_idx.to_double()
    let angle = t * (1.0 + si * 0.2) + si * @math.PI / 3.0
    let dist = 150.0 + 50.0 * @math.sin(t * 2.0 + si)
    let sx = center_x + dist * @math.cos(angle)
    let sy = center_y + dist * @math.sin(angle)
    let shape_hue = (si * 60.0 + t * 80.0) % 360.0
    let (sr, sg, sb) = hsv_to_rgb(shape_hue, 0.9, 0.95)
    let shape_radius = 25.0 + 15.0 * @math.sin(t * 3.0 + si)
    ctx.set_fill_style(
      @raden.Rgba32::new(sr.to_uint(), sg.to_uint(), sb.to_uint(), 180),
    )
    ctx.fill_circle(@raden.Circle::new(sx, sy, shape_radius))
  }
}
