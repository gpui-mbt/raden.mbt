//! 上流 examples の scene 部分の移植 (表示 host を除く)。
//! 描画命令と定数は上流 examples/*.rs のコードをそのまま転記する。
//! `raw_player` に依存する部分 (イベント処理・テクスチャ・debug_text) は
//! ホスト層であり、ここでは画像生成に関わる scene のみを扱う。

use raden::{
    Circle, CompOp, Context, ExtendMode, Gradient, Image, Line, Matrix2D, Path, Pattern,
    PatternFilter, PixelFormat, Rect, Rgba32, StrokeCap, StrokeJoin, premultiply_rgba,
};

/// scene 名から描画関数へ dispatch する。
/// `frame`/`fps` は時間依存 scene のみ使用する (t = frame / fps)。
pub fn render_scene(
    name: &str,
    ctx: &mut Context,
    w: f64,
    h: f64,
    frame: u64,
    fps: u32,
) -> Result<(), String> {
    match name {
        "basic_drawing" => basic_drawing(ctx, w, h),
        "gradient_drawing" => gradient_drawing(ctx, w, h),
        "stroke_drawing" => stroke_drawing(ctx, w, h),
        "blit_clip_pattern_paths" => blit_clip_pattern_paths(ctx, w, h),
        "animation" => {
            if fps == 0 {
                return Err("fps must be > 0".to_string());
            }
            let t = frame as f64 / fps as f64;
            animation_frame(ctx, t, w, h)
        }
        other => return Err(format!("unknown scene: {other}")),
    }
    Ok(())
}

// =============================================================================
// basic_drawing.rs (上流定数をそのまま使用)
// =============================================================================

fn basic_drawing(ctx: &mut Context, w: f64, h: f64) {
    // 青背景 (SrcCopy で全面上書き)
    ctx.set_comp_op(CompOp::SrcCopy);
    ctx.set_fill_style(Rgba32::new(0x20, 0x20, 0x60, 0xFF));
    ctx.fill_rect(&Rect::new(0.0, 0.0, w, h));

    // 半透明矩形を重ねる (SrcOver)
    ctx.set_comp_op(CompOp::SrcOver);

    // 不透明赤矩形
    ctx.set_fill_style(Rgba32::new(0xFF, 0x00, 0x00, 0xFF));
    ctx.fill_rect(&Rect::new(10.0, 10.0, 400.0, 300.0));

    // 半透明緑矩形
    ctx.set_fill_style(Rgba32::new(0x00, 0xFF, 0x00, 0x80));
    ctx.fill_rect(&Rect::new(200.0, 150.0, 400.0, 300.0));

    // 半透明青矩形
    ctx.set_fill_style(Rgba32::new(0x00, 0x00, 0xFF, 0x80));
    ctx.fill_rect(&Rect::new(500.0, 300.0, 400.0, 300.0));
}

// =============================================================================
// gradient_drawing.rs (上流定数をそのまま使用)
// =============================================================================

fn gradient_drawing(ctx: &mut Context, w: f64, h: f64) {
    // 暗い背景
    ctx.set_comp_op(CompOp::SrcCopy);
    ctx.set_fill_style(Rgba32::new(0x1A, 0x1A, 0x2E, 0xFF));
    ctx.fill_rect(&Rect::new(0.0, 0.0, w, h));

    ctx.set_comp_op(CompOp::SrcOver);

    // 上段: Linear グラデーション (Pad / Repeat / Reflect)
    let cell_w = 360.0;
    let cell_h = 200.0;
    let margin = 20.0;
    let base_y = 30.0;

    let extend_modes = [ExtendMode::Pad, ExtendMode::Repeat, ExtendMode::Reflect];

    for (i, &mode) in extend_modes.iter().enumerate() {
        let x = margin + (cell_w + margin) * i as f64;
        let y = base_y;

        let gx0 = x + cell_w * 0.33;
        let gx1 = x + cell_w * 0.67;

        let mut grad = Gradient::new_linear(gx0, y, gx1, y);
        grad.add_stop(0.0, Rgba32::rgb(0x00, 0x80, 0xFF));
        grad.add_stop(0.5, Rgba32::rgb(0xFF, 0xFF, 0x00));
        grad.add_stop(1.0, Rgba32::rgb(0xFF, 0x20, 0x60));
        grad.set_extend_mode(mode);

        ctx.set_fill_style_gradient(&grad);
        ctx.fill_rect(&Rect::new(x, y, cell_w, cell_h));
    }

    // 下段左: Radial グラデーション
    let radial_x = margin;
    let radial_y = base_y + cell_h + margin;
    let radial_w = (w - margin * 3.0) / 2.0;
    let radial_h = h - radial_y - margin;

    let cx = radial_x + radial_w * 0.5;
    let cy = radial_y + radial_h * 0.5;
    let r = radial_w.min(radial_h) * 0.45;

    let fx = cx - r * 0.3;
    let fy = cy - r * 0.2;

    let mut radial = Gradient::new_radial(cx, cy, fx, fy, 0.0, r);
    radial.add_stop(0.0, Rgba32::rgb(0xFF, 0xFF, 0xFF));
    radial.add_stop(0.3, Rgba32::rgb(0xFF, 0xA0, 0x00));
    radial.add_stop(0.7, Rgba32::rgb(0xFF, 0x20, 0x60));
    radial.add_stop(1.0, Rgba32::rgb(0x20, 0x00, 0x40));

    ctx.set_fill_style_gradient(&radial);
    ctx.fill_rect(&Rect::new(radial_x, radial_y, radial_w, radial_h));

    // 下段右: Conic グラデーション
    let conic_x = radial_x + radial_w + margin;
    let conic_y = radial_y;
    let conic_w = radial_w;
    let conic_h = radial_h;

    let ccx = conic_x + conic_w * 0.5;
    let ccy = conic_y + conic_h * 0.5;

    let mut conic = Gradient::new_conic(ccx, ccy, 0.0);
    conic.add_stop(0.0, Rgba32::rgb(0xFF, 0x00, 0x00));
    conic.add_stop(0.17, Rgba32::rgb(0xFF, 0xFF, 0x00));
    conic.add_stop(0.33, Rgba32::rgb(0x00, 0xFF, 0x00));
    conic.add_stop(0.50, Rgba32::rgb(0x00, 0xFF, 0xFF));
    conic.add_stop(0.67, Rgba32::rgb(0x00, 0x00, 0xFF));
    conic.add_stop(0.83, Rgba32::rgb(0xFF, 0x00, 0xFF));
    conic.add_stop(1.0, Rgba32::rgb(0xFF, 0x00, 0x00));

    ctx.set_fill_style_gradient(&conic);
    ctx.fill_rect(&Rect::new(conic_x, conic_y, conic_w, conic_h));
}

// =============================================================================
// stroke_drawing.rs (上流定数をそのまま使用)
// =============================================================================

fn stroke_drawing(ctx: &mut Context, w: f64, h: f64) {
    // 暗い背景
    ctx.set_comp_op(CompOp::SrcCopy);
    ctx.set_fill_style(Rgba32::new(0x1A, 0x1A, 0x2E, 0xFF));
    ctx.fill_rect(&Rect::new(0.0, 0.0, w, h));

    ctx.set_comp_op(CompOp::SrcOver);

    // --- 線分のストローク (異なるキャップ) ---
    ctx.save();

    ctx.set_stroke_style(Rgba32::new(0xFF, 0x60, 0x60, 0xFF));
    ctx.set_stroke_width(8.0);
    ctx.set_stroke_cap(StrokeCap::Butt);
    ctx.stroke_line(&Line::new(50.0, 80.0, 350.0, 80.0));

    ctx.set_stroke_style(Rgba32::new(0x60, 0xFF, 0x60, 0xFF));
    ctx.set_stroke_cap(StrokeCap::Square);
    ctx.stroke_line(&Line::new(50.0, 120.0, 350.0, 120.0));

    ctx.set_stroke_style(Rgba32::new(0x60, 0x60, 0xFF, 0xFF));
    ctx.set_stroke_cap(StrokeCap::Round);
    ctx.stroke_line(&Line::new(50.0, 160.0, 350.0, 160.0));

    ctx.restore();

    // --- 矩形のストローク (異なるジョイン) ---
    ctx.save();

    ctx.set_stroke_style(Rgba32::new(0xFF, 0xA0, 0x00, 0xFF));
    ctx.set_stroke_width(6.0);
    ctx.set_stroke_cap(StrokeCap::Butt);
    ctx.set_stroke_join(StrokeJoin::Bevel);
    ctx.stroke_rect(&Rect::new(50.0, 220.0, 200.0, 150.0));

    ctx.set_stroke_style(Rgba32::new(0x00, 0xFF, 0xA0, 0xFF));
    ctx.set_stroke_join(StrokeJoin::MiterBevel);
    ctx.stroke_rect(&Rect::new(300.0, 220.0, 200.0, 150.0));

    ctx.set_stroke_style(Rgba32::new(0xA0, 0x00, 0xFF, 0xFF));
    ctx.set_stroke_join(StrokeJoin::Round);
    ctx.stroke_rect(&Rect::new(550.0, 220.0, 200.0, 150.0));

    ctx.restore();

    // --- 円のストローク ---
    ctx.save();

    ctx.set_stroke_style(Rgba32::new(0xFF, 0xFF, 0x00, 0xC0));
    ctx.set_stroke_width(4.0);
    ctx.stroke_circle(&Circle::new(900.0, 300.0, 80.0));

    ctx.restore();

    // --- 複雑なパスのストローク ---
    ctx.save();

    ctx.set_stroke_style(Rgba32::new(0xFF, 0x80, 0xC0, 0xFF));
    ctx.set_stroke_width(5.0);
    ctx.set_stroke_cap(StrokeCap::Round);
    ctx.set_stroke_join(StrokeJoin::Round);
    let mut triangle = Path::new();
    triangle.move_to(150.0, 450.0);
    triangle.line_to(300.0, 600.0);
    triangle.line_to(0.0, 600.0);
    triangle.close();
    ctx.stroke_path(&triangle);

    ctx.set_stroke_style(Rgba32::new(0xFF, 0xD7, 0x00, 0xFF));
    ctx.set_stroke_width(3.0);
    ctx.set_stroke_cap(StrokeCap::Round);
    ctx.set_stroke_join(StrokeJoin::MiterBevel);
    ctx.set_stroke_miter_limit(10.0);
    let mut star = Path::new();
    let cx = 500.0;
    let cy = 550.0;
    let outer_r = 80.0;
    let inner_r = 35.0;
    for i in 0..10 {
        let angle = std::f64::consts::PI * 2.0 * (i as f64) / 10.0 - std::f64::consts::FRAC_PI_2;
        let r = if i % 2 == 0 { outer_r } else { inner_r };
        let x = cx + angle.cos() * r;
        let y = cy + angle.sin() * r;
        if i == 0 {
            star.move_to(x, y);
        } else {
            star.line_to(x, y);
        }
    }
    star.close();
    ctx.stroke_path(&star);

    ctx.restore();

    // --- 異なる幅の線分 ---
    ctx.save();

    ctx.set_stroke_cap(StrokeCap::Round);
    ctx.set_stroke_join(StrokeJoin::Round);
    let widths = [1.0, 2.0, 4.0, 8.0, 12.0];
    for (i, &sw) in widths.iter().enumerate() {
        let y = 480.0 + i as f64 * 30.0;
        let brightness = 0x80 + (i as u8) * 0x18;
        ctx.set_stroke_style(Rgba32::new(brightness, brightness, 0xFF, 0xFF));
        ctx.set_stroke_width(sw);
        ctx.stroke_line(&Line::new(700.0, y, 1000.0, y));
    }

    ctx.restore();

    // --- 半透明ストローク ---
    ctx.save();

    ctx.set_stroke_style(Rgba32::new(0xFF, 0x00, 0x00, 0x60));
    ctx.set_stroke_width(20.0);
    ctx.set_stroke_cap(StrokeCap::Round);
    ctx.stroke_circle(&Circle::new(1100.0, 550.0, 100.0));

    ctx.set_stroke_style(Rgba32::new(0x00, 0xFF, 0x00, 0x60));
    ctx.stroke_circle(&Circle::new(1150.0, 500.0, 100.0));

    ctx.restore();
}

// =============================================================================
// blit_clip_pattern_paths.rs (上流定数・タイル生成をそのまま使用)
// =============================================================================

/// チェッカー模様の `Prgb32` 画像 (blit 用)。
fn checkerboard_tile(size: u32) -> Image {
    let mut img = Image::new(size, size, PixelFormat::Prgb32);
    let stride = img.stride();
    let data = img.data_mut();
    let c0 = premultiply_rgba(0xC8, 0x50, 0x50, 0xFF);
    let c1 = premultiply_rgba(0x50, 0xC8, 0xC8, 0xFF);
    let cell = 8u32;
    for y in 0..size {
        for x in 0..size {
            let ix = x / cell;
            let iy = y / cell;
            let c = if (ix + iy).is_multiple_of(2) { c0 } else { c1 };
            let off = y as usize * stride + x as usize * 4;
            data[off..off + 4].copy_from_slice(&c.to_le_bytes());
        }
    }
    img
}

/// 横ストライプの `Prgb32` 画像 (パターン塗り専用)。
fn horizontal_stripe_tile(size: u32) -> Image {
    let mut img = Image::new(size, size, PixelFormat::Prgb32);
    let stride = img.stride();
    let data = img.data_mut();
    let c0 = premultiply_rgba(0xFF, 0xA0, 0x20, 0xFF);
    let c1 = premultiply_rgba(0x20, 0x40, 0xE8, 0xFF);
    let band = 6u32;
    for y in 0..size {
        for x in 0..size {
            let c = if (y / band).is_multiple_of(2) { c0 } else { c1 };
            let off = y as usize * stride + x as usize * 4;
            data[off..off + 4].copy_from_slice(&c.to_le_bytes());
        }
    }
    img
}

fn blit_clip_pattern_paths(ctx: &mut Context, w: f64, h: f64) {
    let tile = checkerboard_tile(56);
    let stripe = horizontal_stripe_tile(48);

    let clip_window = Rect::new(420.0, 80.0, 280.0, 220.0);

    // 背景
    ctx.set_comp_op(CompOp::SrcCopy);
    ctx.set_fill_style(Rgba32::new(0x12, 0x14, 0x22, 0xFF));
    ctx.fill_rect(&Rect::new(0.0, 0.0, w, h));
    ctx.set_comp_op(CompOp::SrcOver);

    // --- blit: 行列で回転した転送 (Nearest) ---
    let half = tile.width() as f64 * 0.5;
    ctx.save();
    ctx.post_translate(220.0, 180.0);
    ctx.post_rotate(0.85);
    ctx.blit_image_at(-half, -half, &tile);
    ctx.restore();

    // --- 矩形クリップ: 円を描くが窓の外は描かれない ---
    ctx.save();
    ctx.clip_to_rect(&clip_window);
    ctx.set_fill_style(Rgba32::new(0xFF, 0xDD, 0x20, 0xFF));
    ctx.fill_circle(&Circle::new(330.0, 190.0, 175.0));
    ctx.restore();

    // --- パターン: ストライプ画像 + Bilinear + スケール ---
    let mut pat = Pattern::new(
        stripe.data(),
        stripe.width(),
        stripe.height(),
        stripe.stride(),
    );
    pat.set_filter(PatternFilter::Bilinear);
    pat.set_transform(Matrix2D::scaling(1.4, 1.4));
    ctx.set_fill_style_pattern(&pat);
    ctx.fill_rect(&Rect::new(80.0, 380.0, 320.0, 240.0));
    ctx.set_fill_style(Rgba32::new(0xFF, 0xFF, 0xFF, 0xFF));

    // --- 拡張パス + せん断した座標系 ---
    ctx.save();
    ctx.post_translate(520.0, 360.0);
    ctx.post_skew(0.12, 0.0);

    let mut p = Path::new();
    // smooth_quad_to: 直前の quad_to が必要
    p.move_to(0.0, 0.0);
    p.quad_to(40.0, -60.0, 80.0, 0.0);
    p.smooth_quad_to(120.0, 0.0);

    // smooth_cubic_to: 直前の cubic_to が必要
    p.move_to(0.0, 80.0);
    p.cubic_to(10.0, 40.0, 50.0, 40.0, 60.0, 80.0);
    p.smooth_cubic_to(110.0, 120.0, 160.0, 80.0);

    // 円錐曲線 (有理二次)
    p.move_to(180.0, 20.0);
    p.conic_to(220.0, 60.0, 260.0, 20.0, 0.85);

    // 楕円弧 (arc_to)
    p.move_to(300.0, 80.0);
    p.arc_to(
        340.0,
        50.0,
        35.0,
        28.0,
        0.0,
        std::f64::consts::PI * 1.2,
        true,
    );

    ctx.set_fill_style(Rgba32::new(0x66, 0xAA, 0xFF, 0xD0));
    ctx.set_stroke_style(Rgba32::new(0xFF, 0xFF, 0xFF, 0xFF));
    ctx.set_stroke_width(2.0);
    ctx.set_stroke_cap(StrokeCap::Round);
    ctx.set_stroke_join(StrokeJoin::Round);
    ctx.fill_path(&p);
    ctx.stroke_path(&p);
    ctx.restore();

    // --- もう一枚 blit (SrcCopy で矩形を上書き。チェッカーを粗く拡大) ---
    ctx.save();
    ctx.set_comp_op(CompOp::SrcCopy);
    ctx.blit_image_rect(
        &Rect::new(900.0, 420.0, 160.0, 120.0),
        &tile,
        Some(Rect::new(
            0.0,
            0.0,
            tile.width() as f64,
            tile.height() as f64,
        )),
    );
    ctx.restore();
}

// =============================================================================
// animation.rs render_frame (上流をそのまま転記)
// =============================================================================

const NUM_WAVES: usize = 5;
const NUM_BALLS: usize = 8;
const NUM_SHAPES: usize = 6;

/// HSV を RGB に変換する (h: 0-360, s: 0-1, v: 0-1)。
fn hsv_to_rgb(h: f64, s: f64, v: f64) -> (u8, u8, u8) {
    let c = v * s;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = v - c;

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
    };

    (
        ((r + m) * 255.0) as u8,
        ((g + m) * 255.0) as u8,
        ((b + m) * 255.0) as u8,
    )
}

fn animation_frame(ctx: &mut Context, t: f64, w: f64, h: f64) {
    // --- 背景: HSV で色相がゆっくり変化する暗い背景 (SrcCopy) ---
    ctx.set_comp_op(CompOp::SrcCopy);
    let bg_hue = (t * 20.0) % 360.0;
    let (br, bg, bb) = hsv_to_rgb(bg_hue, 0.3, 0.15);
    ctx.set_fill_style(Rgba32::rgb(br, bg, bb));
    ctx.fill_all();

    ctx.set_comp_op(CompOp::SrcOver);

    // --- ウェーブパターン: 横方向に並ぶ円が sin 波で上下に動く ---
    for wave_idx in 0..NUM_WAVES {
        let wi = wave_idx as f64;
        let wave_offset = wi * 0.5;
        let wave_amplitude = 50.0 + wi * 20.0;
        let wave_freq = 0.008 + wi * 0.002;
        let wave_speed = 2.0 + wi * 0.3;
        let wave_y_base = h * 0.3 + wi * 80.0;

        let wave_hue = (t * 60.0 + wi * 50.0) % 360.0;
        let (wr, wg, wb) = hsv_to_rgb(wave_hue, 0.8, 0.9);
        ctx.set_fill_style(Rgba32::new(wr, wg, wb, 150));

        let mut x = 0.0;
        while x < w {
            let y =
                wave_y_base + wave_amplitude * (wave_freq * x + t * wave_speed + wave_offset).sin();
            let radius = 8.0 + 4.0 * (t * 3.0 + x * 0.01).sin();
            ctx.fill_circle(&Circle::new(x, y, radius));
            x += 20.0;
        }
    }

    // --- バウンドする円: リサージュ曲線風に動く複数の半透明円 ---
    for ball_idx in 0..NUM_BALLS {
        let bi = ball_idx as f64;
        let freq_x = 0.5 + bi * 0.15;
        let freq_y = 0.7 + bi * 0.12;
        let phase_x = bi * std::f64::consts::PI / 4.0;
        let phase_y = bi * std::f64::consts::PI / 3.0;

        let bx = w * 0.5 + (w * 0.35) * (t * freq_x + phase_x).sin();
        let by = h * 0.5 + (h * 0.3) * (t * freq_y + phase_y).sin();
        let ball_radius = 30.0 + 15.0 * (t * 4.0 + bi).sin();

        let ball_hue = (bi * 45.0 + t * 100.0) % 360.0;
        let (cr, cg, cb) = hsv_to_rgb(ball_hue, 1.0, 1.0);
        ctx.set_fill_style(Rgba32::new(cr, cg, cb, 200));
        ctx.fill_circle(&Circle::new(bx, by, ball_radius));

        // 光沢効果 (小さい白い円、左上寄りに配置)
        ctx.save();
        let hl_radius = ball_radius * 0.3;
        ctx.set_fill_style(Rgba32::new(255, 255, 255, 100));
        ctx.fill_circle(&Circle::new(
            bx - ball_radius * 0.3,
            by - ball_radius * 0.3,
            hl_radius,
        ));
        ctx.restore();
    }

    // --- 回転する円群: 中央周囲を周回する円 ---
    let center_x = w * 0.5;
    let center_y = h * 0.5;
    for shape_idx in 0..NUM_SHAPES {
        let si = shape_idx as f64;
        let angle = t * (1.0 + si * 0.2) + si * std::f64::consts::PI / 3.0;
        let dist = 150.0 + 50.0 * (t * 2.0 + si).sin();
        let sx = center_x + dist * angle.cos();
        let sy = center_y + dist * angle.sin();

        let shape_hue = (si * 60.0 + t * 80.0) % 360.0;
        let (sr, sg, sb) = hsv_to_rgb(shape_hue, 0.9, 0.95);

        let shape_radius = 25.0 + 15.0 * (t * 3.0 + si).sin();
        ctx.set_fill_style(Rgba32::new(sr, sg, sb, 180));
        ctx.fill_circle(&Circle::new(sx, sy, shape_radius));
    }
}
