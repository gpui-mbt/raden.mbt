//! raden-oracle: fixed-SHA Rust reference runner and fail-closed comparator.
//!
//! Subcommands:
//!   generate --fixtures <dir> --out <dir> [--filter <id>]
//!   compare  --manifest <file> --fixtures <dir> --oracle <dir> --candidate <dir> --report <file>
//!   selftest [--work <dir>]

use std::collections::BTreeMap;
use std::time::Instant;
use std::fs;
use std::path::{Path as FsPath, PathBuf};

use raden::{
    CompOp, Context, FillRule, Font, FontData, FontFace, FontFeatureSettings, Gradient,
    GradientStop, Image, Line, Matrix2D, Path, Pattern, PatternFilter, PipelineRuntime,
    PixelFormat, Point, Rect, Rgba32, StrokeCap, StrokeJoin,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

mod scenes;

/// 固定した上流 SHA。Cargo.toml の rev と一致させる。
const UPSTREAM_SHA: &str = "afb752e17a69fef8af981251b68de22a7597ff01";
const ORACLE_VERSION: &str = env!("CARGO_PKG_VERSION");
const RUSTC_VERSION: &str = env!("RADEN_ORACLE_RUSTC");
const BUILD_TARGET: &str = env!("RADEN_ORACLE_TARGET");

// =============================================================================
// Fixture schema v1
// =============================================================================

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct Fixture {
    schema: String,
    fixture_id: String,
    width: u32,
    height: u32,
    pixel_format: String,
    commands: Vec<Command>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
enum Command {
    SetCompOp {
        value: String,
    },
    SetFillRule {
        value: String,
    },
    SetFillStyle {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
    SetStrokeStyle {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
    SetFillGradientLinear {
        x0: f64,
        y0: f64,
        x1: f64,
        y1: f64,
        extend: String,
        stops: Vec<StopSpec>,
    },
    SetFillGradientRadial {
        cx: f64,
        cy: f64,
        fx: f64,
        fy: f64,
        r0: f64,
        r1: f64,
        extend: String,
        stops: Vec<StopSpec>,
    },
    SetFillGradientConic {
        cx: f64,
        cy: f64,
        angle: f64,
        extend: String,
        stops: Vec<StopSpec>,
    },
    SetFillPattern {
        image: InlineImage,
        #[serde(default)]
        origin_x: f64,
        #[serde(default)]
        origin_y: f64,
        extend: String,
        filter: String,
    },
    SetStrokeWidth {
        value: f64,
    },
    SetStrokeCap {
        value: String,
    },
    SetStrokeStartCap {
        value: String,
    },
    SetStrokeEndCap {
        value: String,
    },
    SetStrokeJoin {
        value: String,
    },
    SetStrokeMiterLimit {
        value: f64,
    },
    SetStrokeDash {
        #[serde(default)]
        array: Vec<f64>,
        #[serde(default)]
        offset: f64,
    },
    SetGlobalAlpha {
        value: f64,
    },
    SetFillAlpha {
        value: f64,
    },
    SetStrokeAlpha {
        value: f64,
    },
    Save,
    Restore,
    ClipToRect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
    },
    RestoreClipping,
    ResetMatrix,
    SetMatrix {
        m00: f64,
        m01: f64,
        m10: f64,
        m11: f64,
        m20: f64,
        m21: f64,
    },
    Translate {
        tx: f64,
        ty: f64,
    },
    Scale {
        sx: f64,
        sy: f64,
    },
    Rotate {
        angle: f64,
    },
    RotateAround {
        angle: f64,
        cx: f64,
        cy: f64,
    },
    Skew {
        kx: f64,
        ky: f64,
    },
    PostTranslate {
        tx: f64,
        ty: f64,
    },
    PostScale {
        sx: f64,
        sy: f64,
    },
    PostRotate {
        angle: f64,
    },
    PostSkew {
        kx: f64,
        ky: f64,
    },
    FillRect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
    },
    FillAll,
    FillPath {
        commands: Vec<PathCommandSpec>,
    },
    FillCircle {
        cx: f64,
        cy: f64,
        r: f64,
    },
    FillEllipse {
        cx: f64,
        cy: f64,
        rx: f64,
        ry: f64,
    },
    FillRoundRect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        rx: f64,
        ry: f64,
    },
    FillTriangle {
        x0: f64,
        y0: f64,
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,
    },
    FillPolygon {
        points: Vec<[f64; 2]>,
    },
    FillPie {
        cx: f64,
        cy: f64,
        rx: f64,
        ry: f64,
        start: f64,
        sweep: f64,
    },
    StrokePath {
        commands: Vec<PathCommandSpec>,
    },
    StrokeRect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
    },
    StrokeLine {
        x0: f64,
        y0: f64,
        x1: f64,
        y1: f64,
    },
    StrokeCircle {
        cx: f64,
        cy: f64,
        r: f64,
    },
    StrokeEllipse {
        cx: f64,
        cy: f64,
        rx: f64,
        ry: f64,
    },
    StrokeRoundRect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        rx: f64,
        ry: f64,
    },
    StrokeTriangle {
        x0: f64,
        y0: f64,
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,
    },
    StrokePolygon {
        points: Vec<[f64; 2]>,
    },
    StrokePolyline {
        points: Vec<[f64; 2]>,
    },
    ClearRect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
    },
    ClearAll,
    BlitImageAt {
        x: f64,
        y: f64,
        image: InlineImage,
    },
    BlitImageRect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        image: InlineImage,
        src: Option<[f64; 4]>,
    },
    /// テキスト描画 + シェーピング結果の記録。
    /// `font` は --fonts ディレクトリ直下のファイル名 (パストラバーサル不可)。
    /// `draw` は "fill" | "stroke" | "none" (none は shape のみ記録)。
    Text {
        draw: String,
        font: String,
        #[serde(default)]
        index: u32,
        size: f64,
        x: f64,
        y: f64,
        text: String,
        #[serde(default = "default_true")]
        kern: bool,
        #[serde(default = "default_true")]
        liga: bool,
        #[serde(default = "default_true")]
        clig: bool,
    },
    /// 上流 example の scene 描画 (scenes.rs)。fixture の w/h を使う。
    Scene {
        name: String,
        #[serde(default)]
        frame: u64,
        #[serde(default = "default_fps")]
        fps: u32,
    },
}

fn default_fps() -> u32 {
    60
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct StopSpec {
    offset: f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct InlineImage {
    width: u32,
    height: u32,
    /// Straight (non-premultiplied) RGBA8 pixels, row-major, length = w*h*4.
    rgba8: Vec<u8>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case", deny_unknown_fields)]
enum PathCommandSpec {
    MoveTo { x: f64, y: f64 },
    LineTo { x: f64, y: f64 },
    QuadTo { cx: f64, cy: f64, x: f64, y: f64 },
    ConicTo { cx: f64, cy: f64, x: f64, y: f64, w: f64 },
    CubicTo { c1x: f64, c1y: f64, c2x: f64, c2y: f64, x: f64, y: f64 },
    Close,
}

// =============================================================================
// Execution
// =============================================================================

fn parse_comp_op(s: &str) -> Result<CompOp, String> {
    Ok(match s {
        "SrcOver" => CompOp::SrcOver,
        "SrcCopy" => CompOp::SrcCopy,
        "SrcIn" => CompOp::SrcIn,
        "SrcOut" => CompOp::SrcOut,
        "SrcAtop" => CompOp::SrcAtop,
        "DstOver" => CompOp::DstOver,
        "DstCopy" => CompOp::DstCopy,
        "DstIn" => CompOp::DstIn,
        "DstOut" => CompOp::DstOut,
        "DstAtop" => CompOp::DstAtop,
        "Xor" => CompOp::Xor,
        "Clear" => CompOp::Clear,
        "Plus" => CompOp::Plus,
        "Minus" => CompOp::Minus,
        "Modulate" => CompOp::Modulate,
        "Multiply" => CompOp::Multiply,
        "Screen" => CompOp::Screen,
        "Overlay" => CompOp::Overlay,
        "Darken" => CompOp::Darken,
        "Lighten" => CompOp::Lighten,
        "ColorDodge" => CompOp::ColorDodge,
        "ColorBurn" => CompOp::ColorBurn,
        "LinearBurn" => CompOp::LinearBurn,
        "LinearLight" => CompOp::LinearLight,
        "PinLight" => CompOp::PinLight,
        "HardLight" => CompOp::HardLight,
        "SoftLight" => CompOp::SoftLight,
        "Difference" => CompOp::Difference,
        "Exclusion" => CompOp::Exclusion,
        other => return Err(format!("unknown comp op: {other}")),
    })
}

fn parse_fill_rule(s: &str) -> Result<FillRule, String> {
    Ok(match s {
        "NonZero" => FillRule::NonZero,
        "EvenOdd" => FillRule::EvenOdd,
        other => return Err(format!("unknown fill rule: {other}")),
    })
}

fn parse_cap(s: &str) -> Result<StrokeCap, String> {
    Ok(match s {
        "Butt" => StrokeCap::Butt,
        "Square" => StrokeCap::Square,
        "Round" => StrokeCap::Round,
        other => return Err(format!("unknown cap: {other}")),
    })
}

fn parse_join(s: &str) -> Result<StrokeJoin, String> {
    Ok(match s {
        "MiterClip" => StrokeJoin::MiterClip,
        "MiterBevel" => StrokeJoin::MiterBevel,
        "MiterRound" => StrokeJoin::MiterRound,
        "Bevel" => StrokeJoin::Bevel,
        "Round" => StrokeJoin::Round,
        other => return Err(format!("unknown join: {other}")),
    })
}

fn build_path(specs: &[PathCommandSpec]) -> Path {
    let mut p = Path::new();
    for s in specs {
        match s {
            PathCommandSpec::MoveTo { x, y } => p.move_to(*x, *y),
            PathCommandSpec::LineTo { x, y } => p.line_to(*x, *y),
            PathCommandSpec::QuadTo { cx, cy, x, y } => p.quad_to(*cx, *cy, *x, *y),
            PathCommandSpec::ConicTo { cx, cy, x, y, w } => p.conic_to(*cx, *cy, *x, *y, *w),
            PathCommandSpec::CubicTo {
                c1x,
                c1y,
                c2x,
                c2y,
                x,
                y,
            } => p.cubic_to(*c1x, *c1y, *c2x, *c2y, *x, *y),
            PathCommandSpec::Close => p.close(),
        }
    }
    p
}

fn parse_extend(s: &str) -> Result<raden::ExtendMode, String> {
    Ok(match s {
        "Pad" => raden::ExtendMode::Pad,
        "Repeat" => raden::ExtendMode::Repeat,
        "Reflect" => raden::ExtendMode::Reflect,
        other => return Err(format!("unknown extend mode: {other}")),
    })
}

fn build_gradient_stops(stops: &[StopSpec]) -> Vec<GradientStop> {
    stops
        .iter()
        .map(|s| GradientStop {
            offset: s.offset,
            color: Rgba32::new(s.r, s.g, s.b, s.a),
        })
        .collect()
}

fn apply_stops(grad: &mut Gradient, ext: raden::ExtendMode, stops: &[StopSpec]) {
    for s in build_gradient_stops(stops) {
        grad.add_stop(s.offset, s.color);
    }
    grad.set_extend_mode(ext);
}

fn build_inline_image(spec: &InlineImage) -> Result<Image, String> {
    let len = spec.width as usize * spec.height as usize * 4;
    if spec.rgba8.len() != len {
        return Err(format!(
            "inline image rgba8 length {} != {}",
            spec.rgba8.len(),
            len
        ));
    }
    let mut img = Image::new(spec.width, spec.height, PixelFormat::Prgb32);
    {
        let data = img.data_mut();
        for i in 0..spec.width as usize * spec.height as usize {
            let r = spec.rgba8[i * 4] as u32;
            let g = spec.rgba8[i * 4 + 1] as u32;
            let b = spec.rgba8[i * 4 + 2] as u32;
            let a = spec.rgba8[i * 4 + 3] as u32;
            let px = raden::premultiply_rgba(r as u8, g as u8, b as u8, a as u8);
            data[i * 4..i * 4 + 4].copy_from_slice(&px.to_le_bytes());
        }
    }
    Ok(img)
}

/// フォントファイルを --fonts ディレクトリから読み Font を構築する。
/// `name` はファイル名のみ許可する (パストラバーサル防止)。
fn load_font(
    fonts_dir: &FsPath,
    name: &str,
    index: u32,
    size: f64,
    kern: bool,
    liga: bool,
    clig: bool,
) -> Result<Font, String> {
    if name.is_empty()
        || name.contains('/')
        || name.contains('\\')
        || name.starts_with('.')
    {
        return Err(format!("invalid font name: {name:?}"));
    }
    let path = fonts_dir.join(name);
    let bytes =
        fs::read(&path).map_err(|e| format!("read font {}: {e}", path.display()))?;
    let data = FontData::from_bytes(bytes);
    let face =
        FontFace::from_data(&data, index).map_err(|e| format!("parse font {name}: {e:?}"))?;
    let features = FontFeatureSettings::none()
        .with_kern(kern)
        .with_liga(liga)
        .with_clig(clig);
    Ok(Font::with_features(&face, size, features))
}

/// `Font::shape` の結果を ShapeDump へ写す。
fn shape_dump(font: &Font, text: &str) -> ShapeDump {
    let buf = font.shape(text);
    let mut dump = ShapeDump {
        glyph_ids: Vec::with_capacity(buf.len()),
        clusters: Vec::with_capacity(buf.len()),
        advances: Vec::with_capacity(buf.len()),
        offsets: Vec::with_capacity(buf.len()),
    };
    for i in 0..buf.len() {
        dump.glyph_ids.push(buf.glyph_id(i).unwrap_or(0) as u32);
        dump.clusters.push(buf.cluster(i).unwrap_or(0));
        if let Some(p) = buf.placement(i) {
            dump.advances.push(p.advance);
            dump.offsets.push([p.offset_x, p.offset_y]);
        }
    }
    dump
}

fn run_fixture(fixture: &Fixture, fonts_dir: &FsPath) -> Result<(Image, Vec<ShapeDump>), String> {
    if fixture.schema != "raden.fixture.v1" {
        return Err(format!("unsupported fixture schema: {}", fixture.schema));
    }
    let format = match fixture.pixel_format.as_str() {
        "prgb32" => PixelFormat::Prgb32,
        "xrgb32" => PixelFormat::Xrgb32,
        "a8" => PixelFormat::A8,
        other => return Err(format!("unknown pixel format: {other}")),
    };
    let mut img = Image::new(fixture.width, fixture.height, format);
    let mut runtime = PipelineRuntime::new();
    let mut ctx = Context::new(&mut img, &mut runtime);
    let mut built_images: Vec<Image> = Vec::new();
    let mut shapes: Vec<ShapeDump> = Vec::new();

    for cmd in &fixture.commands {
        match cmd {
            Command::SetCompOp { value } => ctx.set_comp_op(parse_comp_op(value)?),
            Command::SetFillRule { value } => ctx.set_fill_rule(parse_fill_rule(value)?),
            Command::SetFillStyle { r, g, b, a } => {
                ctx.set_fill_style(Rgba32::new(*r, *g, *b, *a))
            }
            Command::SetStrokeStyle { r, g, b, a } => {
                ctx.set_stroke_style(Rgba32::new(*r, *g, *b, *a))
            }
            Command::SetFillGradientLinear {
                x0,
                y0,
                x1,
                y1,
                extend,
                stops,
            } => {
                let ext = parse_extend(extend)?;
                let mut g = Gradient::new_linear(*x0, *y0, *x1, *y1);
                apply_stops(&mut g, ext, stops);
                ctx.set_fill_style_gradient(&g);
            }
            Command::SetFillGradientRadial {
                cx,
                cy,
                fx,
                fy,
                r0,
                r1,
                extend,
                stops,
            } => {
                let ext = parse_extend(extend)?;
                let mut g = Gradient::new_radial(*cx, *cy, *fx, *fy, *r0, *r1);
                apply_stops(&mut g, ext, stops);
                ctx.set_fill_style_gradient(&g);
            }
            Command::SetFillGradientConic {
                cx,
                cy,
                angle,
                extend,
                stops,
            } => {
                let ext = parse_extend(extend)?;
                let mut g = Gradient::new_conic(*cx, *cy, *angle);
                apply_stops(&mut g, ext, stops);
                ctx.set_fill_style_gradient(&g);
            }
            Command::SetFillPattern {
                image,
                origin_x,
                origin_y,
                extend,
                filter,
            } => {
                let img = build_inline_image(image)?;
                let ext = parse_extend(extend)?;
                let filter = match filter.as_str() {
                    "Nearest" => PatternFilter::Nearest,
                    "Bilinear" => PatternFilter::Bilinear,
                    other => return Err(format!("unknown pattern filter: {other}")),
                };
                let mut pattern =
                    Pattern::new(img.data(), img.width(), img.height(), img.stride());
                pattern.set_filter(filter);
                pattern.set_extend_mode(ext);
                pattern.set_origin(*origin_x, *origin_y);
                ctx.set_fill_style_pattern(&pattern);
                built_images.push(img);
            }
            Command::SetStrokeWidth { value } => ctx.set_stroke_width(*value),
            Command::SetStrokeCap { value } => ctx.set_stroke_cap(parse_cap(value)?),
            Command::SetStrokeStartCap { value } => ctx.set_stroke_start_cap(parse_cap(value)?),
            Command::SetStrokeEndCap { value } => ctx.set_stroke_end_cap(parse_cap(value)?),
            Command::SetStrokeJoin { value } => ctx.set_stroke_join(parse_join(value)?),
            Command::SetStrokeMiterLimit { value } => ctx.set_stroke_miter_limit(*value),
            Command::SetStrokeDash { array, offset } => {
                ctx.set_stroke_dash_array(array);
                ctx.set_stroke_dash_offset(*offset);
            }
            Command::SetGlobalAlpha { value } => ctx.set_global_alpha(*value),
            Command::SetFillAlpha { value } => ctx.set_fill_alpha(*value),
            Command::SetStrokeAlpha { value } => ctx.set_stroke_alpha(*value),
            Command::Save => ctx.save(),
            Command::Restore => ctx.restore(),
            Command::ClipToRect { x, y, w, h } => ctx.clip_to_rect(&Rect::new(*x, *y, *w, *h)),
            Command::RestoreClipping => ctx.restore_clipping(),
            Command::ResetMatrix => ctx.reset_matrix(),
            Command::SetMatrix {
                m00,
                m01,
                m10,
                m11,
                m20,
                m21,
            } => {
                ctx.reset_matrix();
                ctx.post_transform(&Matrix2D::new(*m00, *m01, *m10, *m11, *m20, *m21));
            }
            Command::Translate { tx, ty } => ctx.translate(*tx, *ty),
            Command::Scale { sx, sy } => ctx.scale(*sx, *sy),
            Command::Rotate { angle } => ctx.rotate(*angle),
            Command::RotateAround { angle, cx, cy } => ctx.rotate_around(*angle, *cx, *cy),
            Command::Skew { kx, ky } => ctx.skew(*kx, *ky),
            Command::PostTranslate { tx, ty } => ctx.post_translate(*tx, *ty),
            Command::PostScale { sx, sy } => ctx.post_scale(*sx, *sy),
            Command::PostRotate { angle } => ctx.post_rotate(*angle),
            Command::PostSkew { kx, ky } => ctx.post_skew(*kx, *ky),
            Command::FillRect { x, y, w, h } => ctx.fill_rect(&Rect::new(*x, *y, *w, *h)),
            Command::FillAll => ctx.fill_all(),
            Command::FillPath { commands } => {
                let p = build_path(commands);
                ctx.fill_path(&p);
            }
            Command::FillCircle { cx, cy, r } => {
                ctx.fill_circle(&raden::Circle::new(*cx, *cy, *r))
            }
            Command::FillEllipse { cx, cy, rx, ry } => {
                ctx.fill_ellipse(&raden::Ellipse::new(*cx, *cy, *rx, *ry))
            }
            Command::FillRoundRect { x, y, w, h, rx, ry } => {
                ctx.fill_round_rect(&raden::RoundRect::new(*x, *y, *w, *h, *rx, *ry))
            }
            Command::FillTriangle {
                x0,
                y0,
                x1,
                y1,
                x2,
                y2,
            } => ctx.fill_triangle(&raden::Triangle::new(*x0, *y0, *x1, *y1, *x2, *y2)),
            Command::FillPolygon { points } => {
                let pts: Vec<Point> = points.iter().map(|p| Point::new(p[0], p[1])).collect();
                ctx.fill_polygon(&pts);
            }
            Command::FillPie {
                cx,
                cy,
                rx,
                ry,
                start,
                sweep,
            } => ctx.fill_pie(&raden::Arc::new(*cx, *cy, *rx, *ry, *start, *sweep)),
            Command::StrokePath { commands } => {
                let p = build_path(commands);
                ctx.stroke_path(&p);
            }
            Command::StrokeRect { x, y, w, h } => ctx.stroke_rect(&Rect::new(*x, *y, *w, *h)),
            Command::StrokeLine { x0, y0, x1, y1 } => {
                ctx.stroke_line(&Line::new(*x0, *y0, *x1, *y1))
            }
            Command::StrokeCircle { cx, cy, r } => {
                ctx.stroke_circle(&raden::Circle::new(*cx, *cy, *r))
            }
            Command::StrokeEllipse { cx, cy, rx, ry } => {
                ctx.stroke_ellipse(&raden::Ellipse::new(*cx, *cy, *rx, *ry))
            }
            Command::StrokeRoundRect { x, y, w, h, rx, ry } => {
                ctx.stroke_round_rect(&raden::RoundRect::new(*x, *y, *w, *h, *rx, *ry))
            }
            Command::StrokeTriangle {
                x0,
                y0,
                x1,
                y1,
                x2,
                y2,
            } => ctx.stroke_triangle(&raden::Triangle::new(*x0, *y0, *x1, *y1, *x2, *y2)),
            Command::StrokePolygon { points } => {
                let pts: Vec<Point> = points.iter().map(|p| Point::new(p[0], p[1])).collect();
                ctx.stroke_polygon(&pts);
            }
            Command::StrokePolyline { points } => {
                let pts: Vec<Point> = points.iter().map(|p| Point::new(p[0], p[1])).collect();
                ctx.stroke_polyline(&pts);
            }
            Command::ClearRect { x, y, w, h } => ctx.clear_rect(&Rect::new(*x, *y, *w, *h)),
            Command::ClearAll => ctx.clear_all(),
            Command::BlitImageAt { x, y, image } => {
                let img = build_inline_image(image)?;
                ctx.blit_image_at(*x, *y, &img);
                built_images.push(img);
            }
            Command::BlitImageRect {
                x,
                y,
                w,
                h,
                image,
                src,
            } => {
                let img = build_inline_image(image)?;
                let src_rect = src.map(|s| Rect::new(s[0], s[1], s[2], s[3]));
                ctx.blit_image_rect(&Rect::new(*x, *y, *w, *h), &img, src_rect);
                built_images.push(img);
            }
            Command::Text {
                draw,
                font,
                index,
                size,
                x,
                y,
                text,
                kern,
                liga,
                clig,
            } => {
                let f = load_font(fonts_dir, font, *index, *size, *kern, *liga, *clig)?;
                shapes.push(shape_dump(&f, text));
                match draw.as_str() {
                    "fill" => ctx.fill_text(*x, *y, &f, text),
                    "stroke" => ctx.stroke_text(*x, *y, &f, text),
                    "none" => {}
                    other => return Err(format!("unknown text draw mode: {other}")),
                }
            }
            Command::Scene { name, frame, fps } => scenes::render_scene(
                name,
                &mut ctx,
                fixture.width as f64,
                fixture.height as f64,
                *frame,
                *fps,
            )?,
        }
    }
    ctx.end();
    let _ = built_images;
    Ok((img, shapes))
}

// =============================================================================
// Canonical output
// =============================================================================

/// Prgb32 (0xAARRGGBB) を canonical な premultiplied RGBA8 バイト列へ変換する。
fn canonical_bytes(img: &Image) -> Vec<u8> {
    let bpp = img.format().bytes_per_pixel();
    let w = img.width() as usize;
    let h = img.height() as usize;
    let stride = img.stride();
    let data = img.data();
    let mut out = Vec::with_capacity(w * h * 4);
    for y in 0..h {
        for x in 0..w {
            let off = y * stride + x * bpp;
            let word = match bpp {
                4 => u32::from_le_bytes([
                    data[off],
                    data[off + 1],
                    data[off + 2],
                    data[off + 3],
                ]),
                1 => (data[off] as u32) << 24,
                _ => unreachable!(),
            };
            out.push(((word >> 16) & 0xFF) as u8);
            out.push(((word >> 8) & 0xFF) as u8);
            out.push((word & 0xFF) as u8);
            out.push(((word >> 24) & 0xFF) as u8);
        }
    }
    out
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

/// 1 回の `text` コマンドが生成したシェーピング結果の記録。
/// glyph ID / cluster (UTF-8 byte index) / advance / (x,y) offset を
/// そのまま保持し、comparator が oracle/candidate 間で厳密比較する。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct ShapeDump {
    glyph_ids: Vec<u32>,
    clusters: Vec<u32>,
    advances: Vec<f64>,
    offsets: Vec<[f64; 2]>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Meta {
    schema: String,
    fixture_id: String,
    generator: String,
    width: u32,
    height: u32,
    stride: usize,
    pixel_format: String,
    channel_order: String,
    input_sha256: String,
    output_sha256: String,
    output_bytes: usize,
    upstream_sha: String,
    oracle_version: String,
    toolchain: String,
    build_target: String,
    exit_code: i32,
    /// `text` コマンドが存在する fixture では shape 結果列を保持する。
    /// 空なら省略して旧メタとの後方互換を保つ。
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    shapes: Vec<ShapeDump>,
}

fn load_fixture(path: &FsPath) -> Result<(Fixture, String), String> {
    let bytes = fs::read(path).map_err(|e| format!("read {}: {e}", path.display()))?;
    let input_sha = sha256_hex(&bytes);
    let fixture: Fixture =
        serde_json::from_slice(&bytes).map_err(|e| format!("parse {}: {e}", path.display()))?;
    Ok((fixture, input_sha))
}

fn generate_one(
    fixture_path: &FsPath,
    out_dir: &FsPath,
    fonts_dir: &FsPath,
) -> Result<Meta, String> {
    let (fixture, input_sha) = load_fixture(fixture_path)?;
    let (img, shapes) = run_fixture(&fixture, fonts_dir)?;
    let raw = canonical_bytes(&img);
    let output_sha = sha256_hex(&raw);

    fs::create_dir_all(out_dir).map_err(|e| format!("mkdir {}: {e}", out_dir.display()))?;
    let raw_path = out_dir.join(format!("{}.raw", fixture.fixture_id));
    let meta_path = out_dir.join(format!("{}.meta.json", fixture.fixture_id));
    fs::write(&raw_path, &raw).map_err(|e| format!("write {}: {e}", raw_path.display()))?;

    let meta = Meta {
        schema: "raden.result.v1".to_string(),
        fixture_id: fixture.fixture_id.clone(),
        generator: "rust-oracle".to_string(),
        width: fixture.width,
        height: fixture.height,
        stride: img.stride(),
        pixel_format: fixture.pixel_format.clone(),
        channel_order: "rgba8-premultiplied".to_string(),
        input_sha256: input_sha,
        output_sha256: output_sha,
        output_bytes: raw.len(),
        upstream_sha: UPSTREAM_SHA.to_string(),
        oracle_version: ORACLE_VERSION.to_string(),
        toolchain: RUSTC_VERSION.to_string(),
        build_target: BUILD_TARGET.to_string(),
        exit_code: 0,
        shapes,
    };
    let meta_bytes =
        serde_json::to_vec_pretty(&meta).map_err(|e| format!("serialize meta: {e}"))?;
    fs::write(&meta_path, meta_bytes).map_err(|e| format!("write {}: {e}", meta_path.display()))?;
    Ok(meta)
}

// =============================================================================
// Comparator
// =============================================================================

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct ExpectedManifest {
    schema: String,
    fixtures: Vec<String>,
}

#[derive(Debug, Serialize)]
struct FixtureResult {
    fixture_id: String,
    status: String,
    detail: String,
}

#[derive(Debug, Serialize)]
struct CompareReport {
    schema: String,
    oracle_dir: String,
    candidate_dir: String,
    upstream_sha: String,
    gate: String,
    results: Vec<FixtureResult>,
    counts: BTreeMap<String, usize>,
}

fn read_meta(dir: &FsPath, fixture_id: &str) -> Result<Meta, String> {
    let path = dir.join(format!("{fixture_id}.meta.json"));
    let bytes = fs::read(&path).map_err(|e| format!("missing meta {}: {e}", path.display()))?;
    serde_json::from_slice(&bytes).map_err(|e| format!("parse meta {}: {e}", path.display()))
}

fn compare_one(
    fixture_id: &str,
    fixtures_dir: &FsPath,
    oracle_dir: &FsPath,
    candidate_dir: &FsPath,
) -> FixtureResult {
    let fail = |status: &str, detail: String| FixtureResult {
        fixture_id: fixture_id.to_string(),
        status: status.to_string(),
        detail,
    };

    let oracle = match read_meta(oracle_dir, fixture_id) {
        Ok(m) => m,
        Err(e) => return fail("oracle_missing", e),
    };
    let candidate = match read_meta(candidate_dir, fixture_id) {
        Ok(m) => m,
        Err(e) => return fail("candidate_missing", e),
    };

    if oracle.exit_code != 0 {
        return fail("oracle_failed", format!("exit_code={}", oracle.exit_code));
    }
    if candidate.exit_code != 0 {
        return fail("candidate_failed", format!("exit_code={}", candidate.exit_code));
    }
    if oracle.upstream_sha != UPSTREAM_SHA {
        return fail(
            "stale_oracle",
            format!("oracle upstream_sha={}", oracle.upstream_sha),
        );
    }
    for (name, o, c) in [
        ("width", oracle.width as u64, candidate.width as u64),
        ("height", oracle.height as u64, candidate.height as u64),
        (
            "input_sha256",
            u64::from_str_radix(&oracle.input_sha256[..16], 16).unwrap_or(0),
            u64::from_str_radix(&candidate.input_sha256[..16], 16).unwrap_or(0),
        ),
    ] {
        if o != c {
            return fail(
                "metadata_mismatch",
                format!("{name}: oracle={o} candidate={c}"),
            );
        }
    }
    if oracle.pixel_format != candidate.pixel_format {
        return fail(
            "metadata_mismatch",
            format!(
                "pixel_format: oracle={} candidate={}",
                oracle.pixel_format, candidate.pixel_format
            ),
        );
    }
    // `text` コマンドのシェーピング結果 (glyph ID / cluster / advance / offset) を
    // 厳密比較する。ピクセル一致だけでは合字・カーニングの適用有無を
    // 区別できないため、構造レベルでも一致を要求する。
    if oracle.shapes != candidate.shapes {
        return fail(
            "shape_mismatch",
            format!(
                "shapes differ: oracle={} entries candidate={} entries",
                oracle.shapes.len(),
                candidate.shapes.len()
            ),
        );
    }

    // 入力 hash の正: fixture ファイルがある場合は再計算して照合する (fail-closed)。
    let fixture_path = fixtures_dir.join(format!("{fixture_id}.json"));
    if fixture_path.exists() {
        match fs::read(&fixture_path) {
            Ok(bytes) => {
                let sha = sha256_hex(&bytes);
                if sha != oracle.input_sha256 {
                    return fail(
                        "stale_input",
                        format!("fixture file hash {sha} != oracle {}", oracle.input_sha256),
                    );
                }
                if sha != candidate.input_sha256 {
                    return fail(
                        "stale_input",
                        format!(
                            "fixture file hash {sha} != candidate {}",
                            candidate.input_sha256
                        ),
                    );
                }
            }
            Err(e) => return fail("stale_input", format!("read fixture: {e}")),
        }
    }

    let oracle_raw = oracle_dir.join(format!("{fixture_id}.raw"));
    let candidate_raw = candidate_dir.join(format!("{fixture_id}.raw"));
    let ob = match fs::read(&oracle_raw) {
        Ok(b) => b,
        Err(e) => return fail("oracle_missing", format!("read raw: {e}")),
    };
    let cb = match fs::read(&candidate_raw) {
        Ok(b) => b,
        Err(e) => return fail("candidate_missing", format!("read raw: {e}")),
    };

    // meta の output_sha256 が実ファイルと一致することを確認する。
    if sha256_hex(&ob) != oracle.output_sha256 {
        return fail("oracle_tampered", "oracle output hash mismatch".to_string());
    }
    if sha256_hex(&cb) != candidate.output_sha256 {
        return fail(
            "candidate_tampered",
            "candidate output hash does not match meta".to_string(),
        );
    }

    if ob.len() != cb.len() {
        return fail(
            "fail",
            format!("byte length: oracle={} candidate={}", ob.len(), cb.len()),
        );
    }

    if ob == cb {
        FixtureResult {
            fixture_id: fixture_id.to_string(),
            status: "pass".to_string(),
            detail: format!("{} bytes identical", ob.len()),
        }
    } else {
        let first = ob
            .iter()
            .zip(cb.iter())
            .position(|(a, b)| a != b)
            .unwrap_or(0);
        let diff_count = ob.iter().zip(cb.iter()).filter(|(a, b)| a != b).count();
        let max_diff = ob
            .iter()
            .zip(cb.iter())
            .map(|(a, b)| (*a as i32 - *b as i32).abs())
            .max()
            .unwrap_or(0);
        FixtureResult {
            fixture_id: fixture_id.to_string(),
            status: "fail".to_string(),
            detail: format!(
                "raw mismatch: first_diff_byte={} diff_bytes={} max_channel_delta={}",
                first, diff_count, max_diff
            ),
        }
    }
}

fn run_compare(
    manifest_path: &FsPath,
    fixtures_dir: &FsPath,
    oracle_dir: &FsPath,
    candidate_dir: &FsPath,
    report_path: &FsPath,
) -> Result<CompareReport, String> {
    let manifest_bytes =
        fs::read(manifest_path).map_err(|e| format!("read {}: {e}", manifest_path.display()))?;
    let manifest: ExpectedManifest = serde_json::from_slice(&manifest_bytes)
        .map_err(|e| format!("parse {}: {e}", manifest_path.display()))?;
    if manifest.schema != "raden.expected.v1" {
        return Err(format!("unsupported manifest schema: {}", manifest.schema));
    }
    if manifest.fixtures.is_empty() {
        return Err("expected fixture set is empty".to_string());
    }

    let mut results = Vec::new();
    for id in &manifest.fixtures {
        results.push(compare_one(id, fixtures_dir, oracle_dir, candidate_dir));
    }

    let mut counts = BTreeMap::new();
    for r in &results {
        *counts.entry(r.status.clone()).or_insert(0) += 1;
    }
    let gate = if results.iter().all(|r| r.status == "pass") {
        "pass"
    } else {
        "fail"
    };

    let report = CompareReport {
        schema: "raden.compare-report.v1".to_string(),
        oracle_dir: oracle_dir.display().to_string(),
        candidate_dir: candidate_dir.display().to_string(),
        upstream_sha: UPSTREAM_SHA.to_string(),
        gate: gate.to_string(),
        results,
        counts,
    };

    if let Some(parent) = report_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {e}", parent.display()))?;
    }
    let bytes = serde_json::to_vec_pretty(&report).map_err(|e| format!("serialize: {e}"))?;
    fs::write(report_path, bytes).map_err(|e| format!("write {}: {e}", report_path.display()))?;
    Ok(report)
}

// =============================================================================
// Self-test: negative controls for the comparator
// =============================================================================

fn write_synthetic(
    dir: &FsPath,
    id: &str,
    input_sha: &str,
    width: u32,
    height: u32,
    raw: &[u8],
    exit_code: i32,
) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let meta = Meta {
        schema: "raden.result.v1".to_string(),
        fixture_id: id.to_string(),
        generator: "synthetic".to_string(),
        width,
        height,
        stride: (width * 4) as usize,
        pixel_format: "prgb32".to_string(),
        channel_order: "rgba8-premultiplied".to_string(),
        input_sha256: input_sha.to_string(),
        output_sha256: sha256_hex(raw),
        output_bytes: raw.len(),
        upstream_sha: UPSTREAM_SHA.to_string(),
        oracle_version: ORACLE_VERSION.to_string(),
        toolchain: RUSTC_VERSION.to_string(),
        build_target: BUILD_TARGET.to_string(),
        exit_code,
        shapes: Vec::new(),
    };
    fs::write(
        dir.join(format!("{id}.raw")),
        raw,
    )
    .map_err(|e| e.to_string())?;
    fs::write(
        dir.join(format!("{id}.meta.json")),
        serde_json::to_vec_pretty(&meta).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

fn expect_gate(
    name: &str,
    work: &FsPath,
    manifest: &FsPath,
    fixtures: &FsPath,
    oracle: &FsPath,
    candidate: &FsPath,
    expected: &str,
    selftest_results: &mut Vec<(String, bool, String)>,
) {
    let report = work.join("reports").join(format!("{name}.json"));
    match run_compare(manifest, fixtures, oracle, candidate, &report) {
        Ok(r) => {
            let ok = r.gate == expected;
            selftest_results.push((
                name.to_string(),
                ok,
                format!("gate={} (expected {expected})", r.gate),
            ));
        }
        Err(e) => {
            let ok = expected == "error";
            selftest_results.push((name.to_string(), ok, format!("error: {e}")));
        }
    }
}

fn run_selftest(work: &FsPath) -> Result<bool, String> {
    let base = work.join("selftest");
    let fixtures = base.join("fixtures");
    let oracle = base.join("oracle");
    let candidate_ok = base.join("candidate_ok");
    fs::create_dir_all(&fixtures).map_err(|e| e.to_string())?;
    for d in [&oracle, &candidate_ok] {
        fs::create_dir_all(d).map_err(|e| e.to_string())?;
    }

    // 2x2 の fixture と結果を合成する。
    let fixture_json = serde_json::json!({
        "schema": "raden.fixture.v1",
        "fixture_id": "selftest_2x2",
        "width": 2,
        "height": 2,
        "pixel_format": "prgb32",
        "commands": [
            {"op": "set_comp_op", "value": "SrcCopy"},
            {"op": "set_fill_style", "r": 10, "g": 20, "b": 30, "a": 255},
            {"op": "fill_rect", "x": 0.0, "y": 0.0, "w": 2.0, "h": 2.0}
        ]
    });
    let fixture_bytes = serde_json::to_vec_pretty(&fixture_json).map_err(|e| e.to_string())?;
    fs::write(fixtures.join("selftest_2x2.json"), &fixture_bytes).map_err(|e| e.to_string())?;
    let input_sha = sha256_hex(&fixture_bytes);

    let raw: Vec<u8> = vec![10, 20, 30, 255, 10, 20, 30, 255, 10, 20, 30, 255, 10, 20, 30, 255];
    write_synthetic(&oracle, "selftest_2x2", &input_sha, 2, 2, &raw, 0)?;
    write_synthetic(&candidate_ok, "selftest_2x2", &input_sha, 2, 2, &raw, 0)?;

    let manifest_path = base.join("expected.json");
    fs::write(
        &manifest_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "schema": "raden.expected.v1",
            "fixtures": ["selftest_2x2"]
        }))
        .map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;

    let mut results: Vec<(String, bool, String)> = Vec::new();
    expect_gate(
        "identical_passes",
        &base,
        &manifest_path,
        &fixtures,
        &oracle,
        &candidate_ok,
        "pass",
        &mut results,
    );

    // 変異候補をディレクトリごとに作る。
    let mutated = |name: &str,
                       mutate: &dyn Fn(&mut Vec<u8>),
                       meta_mutate: &dyn Fn(&mut Meta)|
     -> Result<PathBuf, String> {
        let dir = base.join(format!("candidate_{name}"));
        let mut bytes = raw.clone();
        mutate(&mut bytes);
        write_synthetic(&dir, "selftest_2x2", &input_sha, 2, 2, &bytes, 0)?;
        // rewrite meta with mutation
        let meta_path = dir.join("selftest_2x2.meta.json");
        let mut meta: Meta =
            serde_json::from_slice(&fs::read(&meta_path).map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?;
        meta_mutate(&mut meta);
        fs::write(
            &meta_path,
            serde_json::to_vec_pretty(&meta).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        Ok(dir)
    };

    let noop = |_: &mut Vec<u8>| {};
    let noop_meta = |_: &mut Meta| {};

    // 1 色変更 (先頭ピクセルの R)
    let d = mutated("color1", &|b: &mut Vec<u8>| b[0] = b[0] ^ 1, &noop_meta)?;
    expect_gate("one_color_changed", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // 1 画素変更 (最後の画素の B)
    let d = mutated("pixel1", &|b: &mut Vec<u8>| {
        let n = b.len();
        b[n - 2] = b[n - 2] ^ 0x40;
    }, &noop_meta)?;
    expect_gate("one_pixel_changed", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // alpha 変更 (全画素の A)
    let d = mutated("alpha", &|b: &mut Vec<u8>| {
        for i in 0..b.len() {
            if i % 4 == 3 {
                b[i] = b[i].saturating_sub(1);
            }
        }
    }, &noop_meta)?;
    expect_gate("alpha_changed", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // 全黒差替え
    let d = mutated("allblack", &|b: &mut Vec<u8>| {
        for (i, v) in b.iter_mut().enumerate() {
            *v = if i % 4 == 3 { 255 } else { 0 };
        }
    }, &noop_meta)?;
    expect_gate("all_black", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // サイズ違い (raw を 1 バイト追加)
    let d = mutated("size", &|b: &mut Vec<u8>| b.push(0), &noop_meta)?;
    expect_gate("size_mismatch", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // 古い入力 hash
    let d = mutated("stale", &noop, &|m: &mut Meta| {
        m.input_sha256 = "0".repeat(64)
    })?;
    expect_gate("stale_input", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // 非ゼロ exit
    let d = base.join("candidate_exit");
    fs::create_dir_all(&d).map_err(|e| e.to_string())?;
    write_synthetic(&d, "selftest_2x2", &input_sha, 2, 2, &raw, 1)?;
    expect_gate("nonzero_exit", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // 欠落 raw
    let d = base.join("candidate_missing_raw");
    fs::create_dir_all(&d).map_err(|e| e.to_string())?;
    write_synthetic(&d, "selftest_2x2", &input_sha, 2, 2, &raw, 0)?;
    fs::remove_file(d.join("selftest_2x2.raw")).map_err(|e| e.to_string())?;
    expect_gate("missing_candidate_raw", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // oracle 欠落
    let d = base.join("oracle_missing");
    fs::create_dir_all(&d).map_err(|e| e.to_string())?;
    expect_gate("missing_oracle", &base, &manifest_path, &fixtures, &d, &candidate_ok, "fail", &mut results);

    // meta が raw と不一致 (改ざん)
    let d = mutated("tampered", &noop, &|m: &mut Meta| {
        m.output_sha256 = "f".repeat(64)
    })?;
    expect_gate("tampered_meta", &base, &manifest_path, &fixtures, &oracle, &d, "fail", &mut results);

    // 空の期待集合
    let empty_manifest = base.join("expected_empty.json");
    fs::write(
        &empty_manifest,
        serde_json::to_vec_pretty(&serde_json::json!({
            "schema": "raden.expected.v1",
            "fixtures": []
        }))
        .map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    expect_gate("empty_expected_set", &base, &empty_manifest, &fixtures, &oracle, &candidate_ok, "error", &mut results);

    // fixture ファイル欠落 + 期待集合にある
    let d = base.join("candidate_ghost");
    fs::create_dir_all(&d).map_err(|e| e.to_string())?;
    let ghost_manifest = base.join("expected_ghost.json");
    fs::write(
        &ghost_manifest,
        serde_json::to_vec_pretty(&serde_json::json!({
            "schema": "raden.expected.v1",
            "fixtures": ["selftest_2x2", "does_not_exist"]
        }))
        .map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    expect_gate("missing_required_fixture", &base, &ghost_manifest, &fixtures, &oracle, &candidate_ok, "fail", &mut results);

    let mut all_ok = true;
    println!("== comparator selftest ==");
    for (name, ok, detail) in &results {
        println!("[{}] {}: {}", if *ok { "OK" } else { "NG" }, name, detail);
        all_ok &= *ok;
    }
    println!(
        "selftest: {} ({} controls)",
        if all_ok { "PASS" } else { "FAIL" },
        results.len()
    );
    Ok(all_ok)
}

// =============================================================================
// CLI
// =============================================================================

fn collect_fixtures(dir: &FsPath, filter: Option<&str>) -> Result<Vec<PathBuf>, String> {
    let mut out = Vec::new();
    let entries = fs::read_dir(dir).map_err(|e| format!("read_dir {}: {e}", dir.display()))?;
    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        if let Some(f) = filter {
            let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
            if stem != f {
                continue;
            }
        }
        out.push(path);
    }
    out.sort();
    Ok(out)
}

fn main() {
    if let Err(e) = run() {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    let mut positional: Vec<String> = Vec::new();
    let mut opts: BTreeMap<String, String> = BTreeMap::new();
    while i < args.len() {
        let a = &args[i];
        if let Some(rest) = a.strip_prefix("--") {
            if rest == "help" {
                positional.push("help".to_string());
                i += 1;
                continue;
            }
            let (key, value) = match rest.split_once('=') {
                Some((k, v)) => (k.to_string(), v.to_string()),
                None => {
                    if i + 1 < args.len() && !args[i + 1].starts_with("--") {
                        i += 1;
                        (rest.to_string(), args[i].clone())
                    } else {
                        (rest.to_string(), "true".to_string())
                    }
                }
            };
            opts.insert(key, value);
        } else {
            positional.push(a.clone());
        }
        i += 1;
    }

    let result: Result<(), String> = match positional.first().map(|s| s.as_str()) {
        Some("generate") => {
            let fixtures_dir = opts
                .get("fixtures")
                .ok_or("generate: --fixtures <dir> is required")?;
            let out_dir = opts.get("out").ok_or("generate: --out <dir> is required")?;
            let filter = opts.get("filter").map(|s| s.as_str());
            // --fonts 未指定時は fixtures の兄弟ディレクトリ fonts を使う
            let fonts_dir = opts
                .get("fonts")
                .map(|s| FsPath::new(s).to_path_buf())
                .unwrap_or_else(|| FsPath::new(fixtures_dir).join("..").join("fonts"));
            let paths = collect_fixtures(FsPath::new(fixtures_dir), filter)?;
            if paths.is_empty() {
                return Err("no fixtures found".to_string());
            }
            let mut metas = Vec::new();
            for p in &paths {
                match generate_one(p, FsPath::new(out_dir), &fonts_dir) {
                    Ok(meta) => {
                        println!(
                            "generated {} ({}x{}, {} bytes, sha256:{}…)",
                            meta.fixture_id,
                            meta.width,
                            meta.height,
                            meta.output_bytes,
                            &meta.output_sha256[..12]
                        );
                        metas.push(meta);
                    }
                    Err(e) => {
                        eprintln!("error: {}: {e}", p.display());
                        std::process::exit(1);
                    }
                }
            }
            let summary = serde_json::json!({
                "schema": "raden.oracle-run.v1",
                "upstream_sha": UPSTREAM_SHA,
                "toolchain": RUSTC_VERSION,
                "build_target": BUILD_TARGET,
                "fixtures": metas.iter().map(|m| serde_json::json!({
                    "fixture_id": m.fixture_id,
                    "input_sha256": m.input_sha256,
                    "output_sha256": m.output_sha256,
                })).collect::<Vec<_>>(),
            });
            let summary_path = FsPath::new(out_dir).join("manifest.json");
            fs::write(
                &summary_path,
                serde_json::to_vec_pretty(&summary).map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
            println!("wrote {}", summary_path.display());
            Ok(())
        }
        Some("bench") => {
            // 性能測定: fixture を N 回描画し cold/warm 統計を出す。
            // 同一 fixture/seed/frame/size で candidate と比較するため、
            // 出力 hash も記録する (ベンチ成功は正しさの代用にしない)。
            let fixtures_dir = opts
                .get("fixtures")
                .ok_or("bench: --fixtures <dir> is required")?;
            let fonts_dir = opts
                .get("fonts")
                .map(|s| FsPath::new(s).to_path_buf())
                .unwrap_or_else(|| FsPath::new(fixtures_dir).join("..").join("..").join("fonts"));
            let frames: usize = opts
                .get("frames")
                .and_then(|s| s.parse().ok())
                .unwrap_or(30);
            let filter = opts.get("filter").map(|s| s.as_str());
            let paths = collect_fixtures(FsPath::new(fixtures_dir), filter)?;
            if paths.is_empty() {
                return Err("no fixtures found".to_string());
            }
            let mut results: Vec<serde_json::Value> = Vec::new();
            for p in &paths {
                let (fixture, input_sha) = load_fixture(p)?;
                // cold run: 初回実行 (JIT/フォント cache 等の初期コストを含む)
                let t0 = Instant::now();
                let (img, _) = run_fixture(&fixture, &fonts_dir)?;
                let cold_ms = t0.elapsed().as_secs_f64() * 1000.0;
                let sha = sha256_hex(&canonical_bytes(&img));
                // warm runs: 毎回 run_fixture 全体 (画像確保込み) を計測
                let mut times: Vec<f64> = Vec::with_capacity(frames);
                for _ in 0..frames {
                    let t = Instant::now();
                    let _ = run_fixture(&fixture, &fonts_dir)?;
                    times.push(t.elapsed().as_secs_f64() * 1000.0);
                }
                times.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let p50 = times[times.len() * 50 / 100];
                let p95 = times[times.len() * 95 / 100];
                let mean = times.iter().sum::<f64>() / times.len() as f64;
                eprintln!(
                    "bench {}: cold={:.2}ms p50={:.2}ms p95={:.2}ms",
                    fixture.fixture_id, cold_ms, p50, p95
                );
                results.push(serde_json::json!({
                    "fixture_id": fixture.fixture_id,
                    "input_sha256": input_sha,
                    "width": fixture.width,
                    "height": fixture.height,
                    "frames": frames,
                    "cold_ms": cold_ms,
                    "warm_p50_ms": p50,
                    "warm_p95_ms": p95,
                    "warm_mean_ms": mean,
                    "output_sha256": sha,
                }));
            }
            let report = serde_json::json!({
                "schema": "raden.bench.v1",
                "generator": "rust-oracle",
                "upstream_sha": UPSTREAM_SHA,
                "toolchain": RUSTC_VERSION,
                "build_target": BUILD_TARGET,
                "results": results,
            });
            match opts.get("out") {
                Some(o) => {
                    fs::write(o, serde_json::to_vec_pretty(&report).map_err(|e| e.to_string())?)
                        .map_err(|e| e.to_string())?;
                    println!("wrote {o}");
                }
                None => println!("{}", serde_json::to_string_pretty(&report).map_err(|e| e.to_string())?),
            }
            Ok(())
        }
        Some("compare") => {
            let manifest = opts
                .get("manifest")
                .ok_or("compare: --manifest <file> is required")?;
            let fixtures_dir = opts
                .get("fixtures")
                .ok_or("compare: --fixtures <dir> is required")?;
            let oracle_dir = opts
                .get("oracle")
                .ok_or("compare: --oracle <dir> is required")?;
            let candidate_dir = opts
                .get("candidate")
                .ok_or("compare: --candidate <dir> is required")?;
            let report = opts.get("report").cloned().unwrap_or("report.json".to_string());
            let r = run_compare(
                FsPath::new(manifest),
                FsPath::new(fixtures_dir),
                FsPath::new(oracle_dir),
                FsPath::new(candidate_dir),
                FsPath::new(&report),
            )?;
            println!(
                "gate: {} ({} fixtures: {:?})",
                r.gate,
                r.results.len(),
                r.counts
            );
            for f in &r.results {
                if f.status != "pass" {
                    println!("  [{}] {}: {}", f.status, f.fixture_id, f.detail);
                }
            }
            if r.gate == "pass" {
                Ok(())
            } else {
                std::process::exit(2);
            }
        }
        Some("selftest") => {
            let work = opts
                .get("work")
                .cloned()
                .unwrap_or_else(|| "target/selftest".to_string());
            let ok = run_selftest(FsPath::new(&work))?;
            if ok {
                Ok(())
            } else {
                std::process::exit(2);
            }
        }
        Some("help") | None => {
            println!(
                "raden-oracle (upstream {UPSTREAM_SHA})\n\n\
                 usage:\n\
                 \x20 generate --fixtures <dir> --out <dir> [--filter <id>]\n\
                 \x20 compare  --manifest <file> --fixtures <dir> --oracle <dir> --candidate <dir> --report <file>\n\
                 \x20 selftest [--work <dir>]"
            );
            Ok(())
        }
        Some(other) => Err(format!("unknown subcommand: {other}")),
    };

    if let Err(e) = result {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
    Ok(())
}
