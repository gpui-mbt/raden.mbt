///|
/// raden-demo: 上流 example scene のヘッドレス実行 CLI。
/// 同じ scene を Native/JS/将来の gpui host で共有するため、
/// 本 CLI はファイル出力と終了コードだけを担当し、
/// 描画は examples/scenes パッケージへ委譲する。
///
/// 使い方:
///   raden-demo --example basic_drawing --output <dir> [--headless]
///              [--width W] [--height H] [--frame N] [--fps F]
///              [--font <path>] [--text <string>]
///
/// 成果物: <dir>/<example>.raw (canonical RGBA8)、
///         <dir>/<example>.bmp (top-down 32bpp BMP)、
///         <dir>/<example>.meta.json (sha256 等の metadata)。
/// blocked example は非 0 で失敗し、場所・原因・対処を出力する。

///|
/// manifest.json の status 相当 (8 本全てをここで追跡する)。
enum ExampleStatus {
  Ready(@scenes.SceneName)
  ReadyFontShaping
  ReadyRadenPlayer
  Blocked(reason~ : String, unblock~ : String)
}

///|
/// 上流 example 名 → 状態。manifest.json と 1 対 1 に対応させること。
fn example_status(name : String) -> ExampleStatus? {
  match name {
    "basic_drawing" => Some(Ready(@scenes.BasicDrawing))
    "gradient_drawing" => Some(Ready(@scenes.GradientDrawing))
    "stroke_drawing" => Some(Ready(@scenes.StrokeDrawing))
    "blit_clip_pattern_paths" => Some(Ready(@scenes.BlitClipPatternPaths))
    "animation" => Some(Ready(@scenes.Animation))
    // font_shaping は scene 型ではなく host 側で font を読み込み、
    // conformance/fixtures/font_shaping_1400x500.json と同じ描画を行う。
    "font_shaping" => Some(ReadyFontShaping)
    // raden_player は shape を animation と共有し、host 側で font を読む。
    "raden_player" => Some(ReadyRadenPlayer)
    "tiger" =>
      Some(
        Blocked(
          reason="tiger_data は AmanithVG (OpenVG) 由来で Blend2D 経由。再配布条件の確認が取れるまでデータを同梱しない",
          unblock="出典台帳と再配布条件の確認後にデータ変換を行う (issues/polished/0008 参照)",
        ),
      )
    _ => None
  }
}

///|
/// 上流 example の既定 (canonical) サイズ。
fn canonical_size(name : String) -> (Int32, Int32) {
  if name == "font_shaping" {
    (1400, 500)
  } else if name == "raden_player" {
    (1920, 1080)
  } else {
    (1280, 720)
  }
}

///|
/// 上流 example の既定 fps。raden_player は 120fps 前提。
fn canonical_fps(name : String) -> Int64 {
  if name == "raden_player" {
    120L
  } else {
    60L
  }
}

///|
/// raw/BMP/meta を同じ Image から書き出す。
async fn write_outputs(
  example : String,
  out_dir : String,
  img : @raden.Image,
  width : Int32,
  height : Int32,
  frame : Int64,
  fps : Int64,
  t : Double,
  font_file : String,
  text : String,
) -> Unit {
  let raw = @scenes.canonical_rgba8(img)
  let bmp = encode_bmp(img) catch {
    e => {
      println("error: \{example}: BMP encode failed: \{e.to_string()}")
      abort("bmp encode failed")
    }
  }
  let raw_path = "\{out_dir}/\{example}.raw"
  let bmp_path = "\{out_dir}/\{example}.bmp"
  let meta_path = "\{out_dir}/\{example}.meta.json"
  let sha = @sha256.sha256_hex(raw[:])
  let bmp_sha = @sha256.sha256_hex(bmp[:])
  @fs.write_file(raw_path, raw, create_mode=@fs.CreateOrTruncate) catch {
    _ => {
      println("error: cannot write \{raw_path}")
      abort("raw write failed")
    }
  }
  @fs.write_file(bmp_path, bmp, create_mode=@fs.CreateOrTruncate) catch {
    _ => {
      println("error: cannot write \{bmp_path}")
      abort("bmp write failed")
    }
  }
  let meta : Json = {
    "schema": "raden.demo.v1",
    "example": example,
    "width": width,
    "height": height,
    "pixel_format": "prgb32",
    "canonical": "rgba8",
    "frame": frame,
    "fps": fps,
    "t": t,
    "bytes": raw.length(),
    "sha256": sha,
    "bmp_bytes": bmp.length(),
    "bmp_sha256": bmp_sha,
    "font_file": font_file,
    "text": text,
  }
  @fs.write_file(
    meta_path,
    meta.stringify(indent=2),
    create_mode=@fs.CreateOrTruncate,
  ) catch {
    _ => {
      println("error: cannot write \{meta_path}")
      abort("meta write failed")
    }
  }
  println(
    "generated \{example} (\{width}x\{height}, frame=\{frame}): \{raw.length()} bytes, sha256=\{sha}",
  )
  println("  raw:  \{raw_path}")
  println("  bmp:  \{bmp_path} (\{bmp.length()} bytes, sha256=\{bmp_sha})")
  println("  meta: \{meta_path}")
}

///|
/// 上流 font_shaping example と同じ描画 (conformance fixture と同一命令)。
async fn render_font_shaping(
  width : Int32,
  height : Int32,
  text : String,
  font_path : String,
) -> @raden.Image {
  let font_data = @fs.read_file(font_path, sync_timestamp=false) catch {
    _ => {
      println("error: cannot read font: \{font_path}")
      println("remediation: pass --font <path> to a TrueType font")
      abort("font read failed")
    }
  }
  let face = @font.FontFace::from_data(
    @font.FontData::from_bytes(font_data.binary()),
    0,
  ) catch {
    @font.FontError::InvalidData(msg) => {
      println("error: invalid font \{font_path}: \{msg}")
      abort("font parse failed")
    }
    @font.FontError::Io(msg) => {
      println("error: font I/O \{font_path}: \{msg}")
      abort("font parse failed")
    }
  }
  let img = @raden.Image::new(width, height, @raden.Prgb32) catch {
    e => {
      println("error: cannot allocate \{width}x\{height}: \{e.to_string()}")
      abort("image allocation failed")
    }
  }
  let ctx = @raden.Context::new(img, @raden.PipelineRuntime::new())
  // 背景を白で塗りつぶす (上流 font_shaping example と同じ)。
  ctx.set_fill_style(@raden.Rgba32::rgb(255, 255, 255))
  ctx.fill_rect(
    @raden.Rect::new(0.0, 0.0, width.to_double(), height.to_double()),
  ) catch {
    e => {
      println("error: background fill failed: \{e.to_string()}")
      abort("font scene failed")
    }
  }
  // ラベル (24px) と本文 (96px)。
  let label = @font.Font::from_face(face, 24.0)
  ctx.set_fill_style(@raden.Rgba32::rgb(64, 64, 64))
  @font.fill_text(
    ctx, 32.0, 48.0, label, "default features (liga / kern / clig ON)",
  ) catch {
    e => {
      println("error: label fill failed: \{e.to_string()}")
      abort("font scene failed")
    }
  }
  @font.fill_text(ctx, 32.0, 364.0, label, "features disabled") catch {
    e => {
      println("error: label fill failed: \{e.to_string()}")
      abort("font scene failed")
    }
  }
  let body = @font.Font::from_face(face, 96.0)
  let body_none = @font.Font::with_features(
    face,
    96.0,
    @font.FontFeatureSettings::none(),
  )
  ctx.set_fill_style(@raden.Rgba32::rgb(0, 0, 0))
  @font.fill_text(ctx, 32.0, 220.0, body, text) catch {
    e => {
      println("error: text fill failed: \{e.to_string()}")
      abort("font scene failed")
    }
  }
  @font.fill_text(ctx, 32.0, 436.0, body_none, text) catch {
    e => {
      println("error: text fill failed: \{e.to_string()}")
      abort("font scene failed")
    }
  }
  ctx.end()
  img
}

///|
/// 上流 raden_player の shape + テキストオーバーレイ。
/// フォントは決定性のため SourceSans3 を使い、actual FPS は target FPS に固定する
/// (上流は Helvetica と wall clock。既知差分 #12/#13)。
async fn render_raden_player(
  width : Int32,
  height : Int32,
  frame : Int64,
  fps : Int64,
  font_path : String,
) -> @raden.Image {
  let font_data = @fs.read_file(font_path, sync_timestamp=false) catch {
    _ => {
      println("error: cannot read font: \{font_path}")
      println("remediation: pass --font <path> to a TrueType font")
      abort("font read failed")
    }
  }
  let face = @font.FontFace::from_data(
    @font.FontData::from_bytes(font_data.binary()),
    0,
  ) catch {
    @font.FontError::InvalidData(msg) => {
      println("error: invalid font \{font_path}: \{msg}")
      abort("font parse failed")
    }
    @font.FontError::Io(msg) => {
      println("error: font I/O \{font_path}: \{msg}")
      abort("font parse failed")
    }
  }
  let img = @raden.Image::new(width, height, @raden.Prgb32) catch {
    e => {
      println("error: cannot allocate \{width}x\{height}: \{e.to_string()}")
      abort("image allocation failed")
    }
  }
  let ctx = @raden.Context::new(img, @raden.PipelineRuntime::new())
  let t = @scenes.animation_t(frame, fps)
  let font_large = @font.Font::from_face(face, 72.0)
  let font_small = @font.Font::from_face(face, 32.0)
  @player.render(
    ctx,
    width.to_double(),
    height.to_double(),
    t,
    font_large,
    font_small,
    frame,
    fps.to_int(),
    fps.to_double(),
  ) catch {
    e => {
      println("error: raden_player scene failed: \{e.to_string()}")
      abort("raden_player scene failed")
    }
  }
  ctx.end()
  img
}

///|
async fn run_demo(
  example : String,
  out_dir : String,
  width : Int32,
  height : Int32,
  frame : Int64,
  fps : Int64,
  font_path : String,
  text : String,
) -> Unit {
  guard example_status(example) is Some(status) else {
    println("error: unknown example: \{example}")
    println(
      "hint: available examples are basic_drawing, gradient_drawing, stroke_drawing, blit_clip_pattern_paths, animation, font_shaping, raden_player (ready) and tiger (blocked)",
    )
    abort("unknown example")
  }
  guard width > 0 && height > 0 else {
    println("error: --width/--height must be positive (got \{width}x\{height})")
    abort("invalid size")
  }
  guard fps > 0L else {
    println("error: --fps must be > 0 (got \{fps})")
    abort("invalid fps")
  }
  guard frame >= 0L else {
    println("error: --frame must be >= 0 (got \{frame})")
    abort("invalid frame")
  }
  @fs.mkdir(out_dir, recursive=true, allow_exist=true) catch {
    _ => {
      println("error: cannot create output directory: \{out_dir}")
      abort("output directory failed")
    }
  }
  let t = @scenes.animation_t(frame, fps)
  match status {
    Ready(scene) => {
      let img = @scenes.render_to_image(scene, width, height, t) catch {
        e => {
          println("error: scene \{example} failed: \{e.to_string()}")
          abort("scene failed")
        }
      }
      write_outputs(example, out_dir, img, width, height, frame, fps, t, "", "")
    }
    ReadyFontShaping => {
      let img = render_font_shaping(width, height, text, font_path)
      write_outputs(
        example, out_dir, img, width, height, frame, fps, t, font_path, text,
      )
    }
    ReadyRadenPlayer => {
      let img = render_raden_player(width, height, frame, fps, font_path)
      write_outputs(
        example, out_dir, img, width, height, frame, fps, t, font_path, "",
      )
    }
    Blocked(reason~, unblock~) => {
      println("error: example \{example} is blocked")
      println("reason: \{reason}")
      println("remediation: \{unblock}")
      abort("example blocked")
    }
  }
}

///|
async fn main {
  let args = @env.args()
  let usage = "usage: raden-demo --example <name> --output <dir> [--headless] [--width W] [--height H] [--frame N] [--fps F] [--font <path>] [--text <string>]"
  guard args.length() >= 2 else {
    println(usage)
    abort("missing arguments")
  }
  let mut example = ""
  let mut out_dir = "."
  let mut width = 0
  let mut height = 0
  let mut frame = 0L
  let mut fps = 60L
  let mut fps_set = false
  let mut font_path = "conformance/fonts/SourceSans3-Regular.ttf"
  let mut text = "ffi AV fl"
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "--example" => {
        example = args[i + 1]
        i = i + 2
      }
      "--output" => {
        out_dir = args[i + 1]
        i = i + 2
      }
      "--width" => {
        width = @string.parse_int(args[i + 1]) catch {
          _ => abort("invalid --width value: \{args[i + 1]}")
        }
        i = i + 2
      }
      "--height" => {
        height = @string.parse_int(args[i + 1]) catch {
          _ => abort("invalid --height value: \{args[i + 1]}")
        }
        i = i + 2
      }
      "--frame" => {
        frame = @string.parse_int64(args[i + 1]) catch {
          _ => abort("invalid --frame value: \{args[i + 1]}")
        }
        i = i + 2
      }
      "--fps" => {
        fps = @string.parse_int64(args[i + 1]) catch {
          _ => abort("invalid --fps value: \{args[i + 1]}")
        }
        fps_set = true
        i = i + 2
      }
      "--font" => {
        font_path = args[i + 1]
        i = i + 2
      }
      "--text" => {
        text = args[i + 1]
        i = i + 2
      }
      "--headless" => i = i + 1
      _ => {
        println(usage)
        abort("unknown argument: \{args[i]}")
      }
    }
  }
  guard example != "" else {
    println(usage)
    abort("--example is required")
  }
  // サイズ/fps 未指定なら canonical 値を使う。
  match example_status(example) {
    Some(Ready(_)) => {
      let (w, h) = canonical_size(example)
      if width == 0 {
        width = w
      }
      if height == 0 {
        height = h
      }
      if !fps_set {
        fps = canonical_fps(example)
      }
    }
    Some(ReadyFontShaping) => {
      let (w, h) = canonical_size(example)
      if width == 0 {
        width = w
      }
      if height == 0 {
        height = h
      }
      if !fps_set {
        fps = canonical_fps(example)
      }
    }
    Some(ReadyRadenPlayer) => {
      let (w, h) = canonical_size(example)
      if width == 0 {
        width = w
      }
      if height == 0 {
        height = h
      }
      if !fps_set {
        fps = canonical_fps(example)
      }
    }
    _ => ()
  }
  run_demo(example, out_dir, width, height, frame, fps, font_path, text)
}
