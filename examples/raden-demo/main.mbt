///|
/// raden-demo: 上流 example scene のヘッドレス実行 CLI。
/// 同じ scene を Native/JS/将来の gpui host で共有するため、
/// 本 CLI はファイル出力と終了コードだけを担当し、
/// 描画は examples/scenes パッケージへ委譲する。
///
/// 使い方:
///   raden-demo --example basic_drawing --output <dir> [--headless]
///              [--width W] [--height H] [--frame N] [--fps F]
///
/// 成果物: <dir>/<example>.raw (canonical RGBA8) と
///         <dir>/<example>.meta.json (sha256 等の metadata)。
/// blocked example は非 0 で失敗し、場所・原因・対処を出力する。

///|
/// manifest.json の status 相当 (8 本全てをここで追跡する)。
enum ExampleStatus {
  Ready(@scenes.SceneName)
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
    "tiger" =>
      Some(
        Blocked(
          reason="tiger_data は AmanithVG (OpenVG) 由来で Blend2D 経由。再配布条件の確認が取れるまでデータを同梱しない",
          unblock="出典台帳と再配布条件の確認後にデータ変換を行う (issues/polished/0008 参照)",
        ),
      )
    "raden_player" =>
      Some(
        Blocked(
          reason="fill_text (Font/FontFace) が必要",
          unblock="RADEN-0011 の font 実装後に scene を有効化",
        ),
      )
    "font_shaping" =>
      Some(
        Blocked(
          reason="FontData/FontFace/FontFeatureSettings が必要",
          unblock="RADEN-0011 の font 実装後に有効化",
        ),
      )
    _ => None
  }
}

///|
/// 上流 example の既定 (canonical) サイズ。
fn canonical_size(name : @scenes.SceneName) -> (Int32, Int32) {
  match name {
    @scenes.Animation => (1280, 720)
    _ => (1280, 720)
  }
}

///|
async fn run_demo(
  example : String,
  out_dir : String,
  width : Int32,
  height : Int32,
  frame : Int64,
  fps : Int64,
) -> Unit {
  guard example_status(example) is Some(status) else {
    println("error: unknown example: \{example}")
    println(
      "hint: available examples are basic_drawing, gradient_drawing, stroke_drawing, blit_clip_pattern_paths, animation (ready) and tiger, raden_player, font_shaping (blocked)",
    )
    abort("unknown example")
  }
  let scene = match status {
    Ready(s) => s
    Blocked(reason~, unblock~) => {
      println("error: example \{example} is blocked")
      println("reason: \{reason}")
      println("remediation: \{unblock}")
      abort("example blocked")
    }
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

  let t = @scenes.animation_t(frame, fps)
  let raw = @scenes.render_to_rgba8(scene, width, height, t)
  let raw_path = "\{out_dir}/\{example}.raw"
  let meta_path = "\{out_dir}/\{example}.meta.json"
  let sha = @sha256.sha256_hex(raw[:])
  @fs.write_file(raw_path, raw, create_mode=@fs.CreateOrTruncate)
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
  }
  @fs.write_file(
    meta_path,
    meta.stringify(indent=2),
    create_mode=@fs.CreateOrTruncate,
  )
  println(
    "generated \{example} (\{width}x\{height}, frame=\{frame}): \{raw.length()} bytes, sha256=\{sha}",
  )
  println("  raw:  \{raw_path}")
  println("  meta: \{meta_path}")
}

///|
async fn main {
  let args = @env.args()
  let usage = "usage: raden-demo --example <name> --output <dir> [--headless] [--width W] [--height H] [--frame N] [--fps F]"
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
  // サイズ未指定なら canonical サイズを使う。
  if width == 0 || height == 0 {
    match example_status(example) {
      Some(Ready(scene)) => {
        let (w, h) = canonical_size(scene)
        if width == 0 {
          width = w
        }
        if height == 0 {
          height = h
        }
      }
      _ => ()
    }
  }
  run_demo(example, out_dir, width, height, frame, fps)
}
