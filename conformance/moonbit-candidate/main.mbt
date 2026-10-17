///|
/// raden MoonBit 実装の conformance candidate runner。
///
/// `conformance/rust-oracle` と同じ fixture schema / 出力形式で動作し、
/// comparator が oracle/candidate を同一形式で比較できるようにする。
///
///   moonbit-candidate generate --fixtures <dir> --out <dir> [--filter <id>]
///
/// 出力:
///   <id>.raw       canonical premultiplied RGBA8 (oracle と同じ並び)
///   <id>.meta.json schema "raden.result.v1" (oracle の Meta と同じキー)
/// コマンド実行が失敗した fixture は exit_code=2 の meta のみを書き、
/// 成功したかのような成果物は絶対に出さない。

///|
/// 固定した上流 SHA。oracle の UPSTREAM_SHA / upstream.lock.json と一致させる。
let upstream_sha : String = "afb752e17a69fef8af981251b68de22a7597ff01"

///|
/// Object 型 Json のキー参照。非 Object や欠落は None。
fn get(j : Json, key : String) -> Json? {
  if j is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

///|
/// JSON 数値フィールドの取得。欠落・非数値はエラー。
fn json_num(j : Json, key : String) -> Double raise {
  match get(j, key) {
    Some(Number(n, ..)) => n
    _ => raise @raden.InvalidInput("missing or non-number field: \{key}")
  }
}

///|
/// JSON 文字列フィールドの取得。
fn json_str(j : Json, key : String) -> String raise {
  match get(j, key) {
    Some(String(s)) => s
    _ => raise @raden.InvalidInput("missing or non-string field: \{key}")
  }
}

///|
/// JSON 配列フィールドの取得。
fn json_arr(j : Json, key : String) -> Array[Json] raise {
  match get(j, key) {
    Some(Array(a)) => a
    _ => raise @raden.InvalidInput("missing or non-array field: \{key}")
  }
}

///|
/// CompOp 名のパース。oracle の parse_comp_op と同名を受理する。
fn parse_comp_op(s : String) -> @raden.CompOp raise {
  match s {
    "SrcOver" => @raden.SrcOver
    "SrcCopy" => @raden.SrcCopy
    "SrcIn" => @raden.SrcIn
    "SrcOut" => @raden.SrcOut
    "SrcAtop" => @raden.SrcAtop
    "DstOver" => @raden.DstOver
    "DstCopy" => @raden.DstCopy
    "DstIn" => @raden.DstIn
    "DstOut" => @raden.DstOut
    "DstAtop" => @raden.DstAtop
    "Xor" => @raden.Xor
    "Clear" => @raden.Clear
    "Plus" => @raden.Plus
    "Minus" => @raden.Minus
    "Modulate" => @raden.Modulate
    "Multiply" => @raden.Multiply
    "Screen" => @raden.Screen
    "Overlay" => @raden.Overlay
    "Darken" => @raden.Darken
    "Lighten" => @raden.Lighten
    "ColorDodge" => @raden.ColorDodge
    "ColorBurn" => @raden.ColorBurn
    "LinearBurn" => @raden.LinearBurn
    "LinearLight" => @raden.LinearLight
    "PinLight" => @raden.PinLight
    "HardLight" => @raden.HardLight
    "SoftLight" => @raden.SoftLight
    "Difference" => @raden.Difference
    "Exclusion" => @raden.Exclusion
    other => raise @raden.InvalidInput("unknown comp op: \{other}")
  }
}

///|
fn parse_fill_rule(s : String) -> @raden.FillRule raise {
  match s {
    "NonZero" => @raden.NonZero
    "EvenOdd" => @raden.EvenOdd
    other => raise @raden.InvalidInput("unknown fill rule: \{other}")
  }
}

///|
fn parse_cap(s : String) -> @raden.StrokeCap raise {
  match s {
    "Butt" => @raden.Butt
    "Square" => @raden.Square
    "Round" => @raden.Round
    other => raise @raden.InvalidInput("unknown cap: \{other}")
  }
}

///|
fn parse_join(s : String) -> @raden.StrokeJoin raise {
  match s {
    "MiterClip" => @raden.MiterClip
    "MiterBevel" => @raden.MiterBevel
    "MiterRound" => @raden.MiterRound
    "Bevel" => @raden.Bevel
    "Round" => @raden.Round
    other => raise @raden.InvalidInput("unknown join: \{other}")
  }
}

///|
/// JSON から straight-alpha u8 チャネルを読み Rgba32 を作る。
fn json_rgba(j : Json) -> @raden.Rgba32 raise {
  @raden.Rgba32::new(
    json_num(j, "r").to_uint(),
    json_num(j, "g").to_uint(),
    json_num(j, "b").to_uint(),
    json_num(j, "a").to_uint(),
  )
}

///|
/// JSON の [x, y] 点列を Point 配列へ変換する。
fn json_points(j : Json, key : String) -> Array[@raden.Point] raise {
  let pts : Array[@raden.Point] = []
  for p in json_arr(j, key) {
    if p is Array(xy) {
      if xy.length() == 2 && xy[0] is Number(x, ..) && xy[1] is Number(y, ..) {
        pts.push(@raden.Point::new(x, y))
        continue
      }
    }
    raise @raden.InvalidInput("invalid point in \{key}")
  }
  pts
}

///|
/// ExtendMode 名のパース。oracle の parse_extend と同名を受理する。
fn parse_extend(s : String) -> @raden.ExtendMode raise {
  match s {
    "Pad" => @raden.Pad
    "Repeat" => @raden.Repeat
    "Reflect" => @raden.Reflect
    other => raise @raden.InvalidInput("unknown extend mode: \{other}")
  }
}

///|
/// グラデーションに stops と extend モードを適用する。
/// oracle の apply_stops に対応 (停止点を順に add_stop してから extend を設定)。
fn apply_stops(
  grad : @raden.Gradient,
  ext : @raden.ExtendMode,
  stops : Array[Json],
) -> Unit raise {
  for s in stops {
    grad.add_stop(json_num(s, "offset"), json_rgba(s)) |> ignore
  }
  grad.set_extend_mode(ext) |> ignore
}

///|
/// fixture の path command 列を Path へ変換する。
fn build_path(specs : Array[Json]) -> @raden.Path raise {
  let p = @raden.Path::new()
  for s in specs {
    match json_str(s, "cmd") {
      "move_to" => p.move_to(json_num(s, "x"), json_num(s, "y"))
      "line_to" => p.line_to(json_num(s, "x"), json_num(s, "y"))
      "quad_to" =>
        p.quad_to(
          json_num(s, "cx"),
          json_num(s, "cy"),
          json_num(s, "x"),
          json_num(s, "y"),
        )
      "conic_to" =>
        p.conic_to(
          json_num(s, "cx"),
          json_num(s, "cy"),
          json_num(s, "x"),
          json_num(s, "y"),
          json_num(s, "w"),
        )
      "cubic_to" =>
        p.cubic_to(
          json_num(s, "c1x"),
          json_num(s, "c1y"),
          json_num(s, "c2x"),
          json_num(s, "c2y"),
          json_num(s, "x"),
          json_num(s, "y"),
        )
      "close" => p.close()
      other => raise @raden.InvalidInput("unknown path cmd: \{other}")
    }
  }
  p
}

///|
/// inline image 指定から Image を作る。straight RGBA8 → Prgb32。
/// blit ソースは上流同様 Prgb32/Xrgb32 のみを想定する。
fn build_inline_image(spec : Json) -> @raden.Image raise {
  let w = json_num(spec, "width").to_int()
  let h = json_num(spec, "height").to_int()
  let arr = json_arr(spec, "rgba8")
  let bytes = FixedArray::make(arr.length(), b'\x00')
  for i, v in arr {
    if v is Number(n, ..) {
      bytes[i] = n.to_int().to_byte()
    } else {
      raise @raden.InvalidInput("non-number in rgba8")
    }
  }
  @raden.Image::from_rgba8(w, h, @raden.Prgb32, Bytes::from_array(bytes[:])[:])
}

///|
/// fixture JSON を実行して描画済み Image を返す。
/// 未対応 op は必ずエラーとして失敗させる。
/// `text` コマンド用のフォント読み込み。
/// `name` は fonts_dir 直下のファイル名のみ許可する
/// (oracle と同じくパストラバーサルを拒否する)。
async fn load_font(
  fonts_dir : String,
  name : String,
  index : Int32,
  size : Double,
  kern : Bool,
  liga : Bool,
  clig : Bool,
) -> @font.Font {
  if name.is_empty() ||
    name.contains("/") ||
    name.contains("\\") ||
    name.has_prefix(".") {
    raise @raden.InvalidInput("invalid font name: \{name}")
  }
  let data = @fs.read_file("\{fonts_dir}/\{name}", sync_timestamp=false)
  let font_data = @font.FontData::from_bytes(data.binary())
  let face = @font.FontFace::from_data(font_data, index)
  let features = @font.FontFeatureSettings::none()
    .with_kern(kern)
    .with_liga(liga)
    .with_clig(clig)
  @font.Font::with_features(face, size, features)
}

///|
/// `Font::shape` の結果を oracle の ShapeDump と同じキー構成の Json へ写す。
/// glyph ID / cluster (UTF-8 byte index) / advance / (x,y) offset を保持し、
/// comparator が oracle/candidate 間で厳密比較する。
fn shape_dump_json(font : @font.Font, text : String) -> Json {
  let buf = font.shape(text)
  let glyph_ids : Array[Json] = []
  let clusters : Array[Json] = []
  let advances : Array[Json] = []
  let offsets : Array[Json] = []
  for i in 0..<buf.length() {
    glyph_ids.push(Json(buf.glyph_id(i).unwrap_or(0)))
    clusters.push(Json(buf.cluster(i).unwrap_or(0)))
    match buf.placement(i) {
      Some(p) => {
        advances.push(Json(p.advance))
        offsets.push(Json([Json(p.offset_x), Json(p.offset_y)]))
      }
      None => ()
    }
  }
  {
    "glyph_ids": Json(glyph_ids),
    "clusters": Json(clusters),
    "advances": Json(advances),
    "offsets": Json(offsets),
  }
}

///|
async fn run_fixture(
  fixture : Json,
  fonts_dir : String,
) -> (@raden.Image, Array[Json]) {
  let format = match json_str(fixture, "pixel_format") {
    "prgb32" => @raden.Prgb32
    "xrgb32" => @raden.Xrgb32
    "a8" => @raden.A8
    other => raise @raden.InvalidInput("unknown pixel format: \{other}")
  }
  let img = @raden.Image::new(
    json_num(fixture, "width").to_int(),
    json_num(fixture, "height").to_int(),
    format,
  )
  let runtime = @raden.PipelineRuntime::new()
  let ctx = @raden.Context::new(img, runtime)
  let shapes : Array[Json] = []
  for cmd in json_arr(fixture, "commands") {
    match json_str(cmd, "op") {
      "set_comp_op" => ctx.set_comp_op(parse_comp_op(json_str(cmd, "value")))
      "set_fill_rule" =>
        ctx.set_fill_rule(parse_fill_rule(json_str(cmd, "value")))
      "set_fill_style" => ctx.set_fill_style(json_rgba(cmd))
      "set_stroke_style" => ctx.set_stroke_style(json_rgba(cmd))
      "set_fill_gradient_linear" => {
        let g = @raden.Gradient::new_linear(
          json_num(cmd, "x0"),
          json_num(cmd, "y0"),
          json_num(cmd, "x1"),
          json_num(cmd, "y1"),
        )
        apply_stops(
          g,
          parse_extend(json_str(cmd, "extend")),
          json_arr(cmd, "stops"),
        )
        ctx.set_fill_style_gradient(g)
      }
      "set_fill_gradient_radial" => {
        // oracle のフィールド順は (cx, cy, fx, fy, r0, r1)。
        // raden の Radial は現状 (x0,y0,r0) のみを描画に使う。
        let g = @raden.Gradient::new_radial(
          json_num(cmd, "cx"),
          json_num(cmd, "cy"),
          json_num(cmd, "fx"),
          json_num(cmd, "fy"),
          json_num(cmd, "r0"),
          json_num(cmd, "r1"),
        )
        apply_stops(
          g,
          parse_extend(json_str(cmd, "extend")),
          json_arr(cmd, "stops"),
        )
        ctx.set_fill_style_gradient(g)
      }
      "set_fill_gradient_conic" => {
        let g = @raden.Gradient::new_conic(
          json_num(cmd, "cx"),
          json_num(cmd, "cy"),
          json_num(cmd, "angle"),
        )
        apply_stops(
          g,
          parse_extend(json_str(cmd, "extend")),
          json_arr(cmd, "stops"),
        )
        ctx.set_fill_style_gradient(g)
      }
      "set_fill_pattern" => {
        let img = build_inline_image(get(cmd, "image").unwrap())
        let ext = parse_extend(json_str(cmd, "extend"))
        let filter = match json_str(cmd, "filter") {
          "Nearest" => @raden.Nearest
          "Bilinear" => @raden.Bilinear
          other => raise @raden.InvalidInput("unknown pattern filter: \{other}")
        }
        let pattern = @raden.Pattern::from_image(img)
        pattern.set_filter(filter) |> ignore
        pattern.set_extend_mode(ext) |> ignore
        // oracle は serde(default) で origin_x/origin_y = 0 を許容する。
        let origin_x = match get(cmd, "origin_x") {
          Some(Number(n, ..)) => n
          _ => 0.0
        }
        let origin_y = match get(cmd, "origin_y") {
          Some(Number(n, ..)) => n
          _ => 0.0
        }
        pattern.set_origin(origin_x, origin_y) |> ignore
        ctx.set_fill_style_pattern(pattern)
      }
      "set_stroke_width" => ctx.set_stroke_width(json_num(cmd, "value"))
      "set_stroke_cap" => ctx.set_stroke_cap(parse_cap(json_str(cmd, "value")))
      "set_stroke_start_cap" =>
        ctx.set_stroke_start_cap(parse_cap(json_str(cmd, "value")))
      "set_stroke_end_cap" =>
        ctx.set_stroke_end_cap(parse_cap(json_str(cmd, "value")))
      "set_stroke_join" =>
        ctx.set_stroke_join(parse_join(json_str(cmd, "value")))
      "set_stroke_miter_limit" =>
        ctx.set_stroke_miter_limit(json_num(cmd, "value"))
      "set_stroke_dash" => {
        let dash : Array[Double] = []
        for v in json_arr(cmd, "array") {
          if v is Number(n, ..) {
            dash.push(n)
          }
        }
        ctx.set_stroke_dash_array(dash[:])
        ctx.set_stroke_dash_offset(json_num(cmd, "offset"))
      }
      "set_global_alpha" => ctx.set_global_alpha(json_num(cmd, "value"))
      "set_fill_alpha" => ctx.set_fill_alpha(json_num(cmd, "value"))
      "set_stroke_alpha" => ctx.set_stroke_alpha(json_num(cmd, "value"))
      "save" => ctx.save()
      "restore" => ctx.restore()
      "clip_to_rect" =>
        ctx.clip_to_rect(
          @raden.Rect::new(
            json_num(cmd, "x"),
            json_num(cmd, "y"),
            json_num(cmd, "w"),
            json_num(cmd, "h"),
          ),
        )
      "restore_clipping" => ctx.restore_clipping()
      "reset_matrix" => ctx.reset_matrix()
      "set_matrix" => {
        ctx.reset_matrix()
        ctx.post_transform(
          @raden.Matrix2D::new(
            json_num(cmd, "m00"),
            json_num(cmd, "m01"),
            json_num(cmd, "m10"),
            json_num(cmd, "m11"),
            json_num(cmd, "m20"),
            json_num(cmd, "m21"),
          ),
        )
      }
      "translate" => ctx.translate(json_num(cmd, "tx"), json_num(cmd, "ty"))
      "scale" => ctx.scale(json_num(cmd, "sx"), json_num(cmd, "sy"))
      "rotate" => ctx.rotate(json_num(cmd, "angle"))
      "rotate_around" =>
        ctx.rotate_around(
          json_num(cmd, "angle"),
          json_num(cmd, "cx"),
          json_num(cmd, "cy"),
        )
      "skew" => ctx.skew(json_num(cmd, "kx"), json_num(cmd, "ky"))
      "post_translate" =>
        ctx.post_translate(json_num(cmd, "tx"), json_num(cmd, "ty"))
      "post_scale" => ctx.post_scale(json_num(cmd, "sx"), json_num(cmd, "sy"))
      "post_rotate" => ctx.post_rotate(json_num(cmd, "angle"))
      "post_skew" => ctx.post_skew(json_num(cmd, "kx"), json_num(cmd, "ky"))
      "fill_rect" =>
        ctx.fill_rect(
          @raden.Rect::new(
            json_num(cmd, "x"),
            json_num(cmd, "y"),
            json_num(cmd, "w"),
            json_num(cmd, "h"),
          ),
        )
      "fill_all" => ctx.fill_all()
      "fill_path" => ctx.fill_path(build_path(json_arr(cmd, "commands")))
      "fill_circle" =>
        ctx.fill_circle(
          @raden.Circle::new(
            json_num(cmd, "cx"),
            json_num(cmd, "cy"),
            json_num(cmd, "r"),
          ),
        )
      "fill_ellipse" =>
        ctx.fill_ellipse(
          @raden.Ellipse::new(
            json_num(cmd, "cx"),
            json_num(cmd, "cy"),
            json_num(cmd, "rx"),
            json_num(cmd, "ry"),
          ),
        )
      "fill_round_rect" =>
        ctx.fill_round_rect(
          @raden.RoundRect::new(
            json_num(cmd, "x"),
            json_num(cmd, "y"),
            json_num(cmd, "w"),
            json_num(cmd, "h"),
            json_num(cmd, "rx"),
            json_num(cmd, "ry"),
          ),
        )
      "fill_triangle" =>
        ctx.fill_triangle(
          @raden.Triangle::new(
            json_num(cmd, "x0"),
            json_num(cmd, "y0"),
            json_num(cmd, "x1"),
            json_num(cmd, "y1"),
            json_num(cmd, "x2"),
            json_num(cmd, "y2"),
          ),
        )
      "fill_polygon" => ctx.fill_polygon(json_points(cmd, "points"))
      "fill_pie" =>
        ctx.fill_pie(
          @raden.Arc::new(
            json_num(cmd, "cx"),
            json_num(cmd, "cy"),
            json_num(cmd, "rx"),
            json_num(cmd, "ry"),
            json_num(cmd, "start"),
            json_num(cmd, "sweep"),
          ),
        )
      "stroke_path" => ctx.stroke_path(build_path(json_arr(cmd, "commands")))
      "stroke_rect" =>
        ctx.stroke_rect(
          @raden.Rect::new(
            json_num(cmd, "x"),
            json_num(cmd, "y"),
            json_num(cmd, "w"),
            json_num(cmd, "h"),
          ),
        )
      "stroke_line" =>
        ctx.stroke_line(
          @raden.Line::new(
            json_num(cmd, "x0"),
            json_num(cmd, "y0"),
            json_num(cmd, "x1"),
            json_num(cmd, "y1"),
          ),
        )
      "stroke_circle" =>
        ctx.stroke_circle(
          @raden.Circle::new(
            json_num(cmd, "cx"),
            json_num(cmd, "cy"),
            json_num(cmd, "r"),
          ),
        )
      "stroke_ellipse" =>
        ctx.stroke_ellipse(
          @raden.Ellipse::new(
            json_num(cmd, "cx"),
            json_num(cmd, "cy"),
            json_num(cmd, "rx"),
            json_num(cmd, "ry"),
          ),
        )
      "stroke_round_rect" =>
        ctx.stroke_round_rect(
          @raden.RoundRect::new(
            json_num(cmd, "x"),
            json_num(cmd, "y"),
            json_num(cmd, "w"),
            json_num(cmd, "h"),
            json_num(cmd, "rx"),
            json_num(cmd, "ry"),
          ),
        )
      "stroke_triangle" =>
        ctx.stroke_triangle(
          @raden.Triangle::new(
            json_num(cmd, "x0"),
            json_num(cmd, "y0"),
            json_num(cmd, "x1"),
            json_num(cmd, "y1"),
            json_num(cmd, "x2"),
            json_num(cmd, "y2"),
          ),
        )
      "stroke_polygon" => ctx.stroke_polygon(json_points(cmd, "points"))
      "stroke_polyline" => ctx.stroke_polyline(json_points(cmd, "points"))
      "clear_rect" =>
        ctx.clear_rect(
          @raden.Rect::new(
            json_num(cmd, "x"),
            json_num(cmd, "y"),
            json_num(cmd, "w"),
            json_num(cmd, "h"),
          ),
        )
      "clear_all" => ctx.clear_all()
      "blit_image_at" =>
        ctx.blit_image_at(
          json_num(cmd, "x"),
          json_num(cmd, "y"),
          build_inline_image(get(cmd, "image").unwrap()),
        )
      "blit_image_rect" => {
        let src_rect = match get(cmd, "src") {
          Some(Null) | None => None
          Some(Array(a)) =>
            if a.length() == 4 {
              let nums : Array[Double] = []
              for v in a {
                if v is Number(n, ..) {
                  nums.push(n)
                }
              }
              if nums.length() != 4 {
                raise @raden.InvalidInput("src must be [x, y, w, h]")
              }
              Some(@raden.Rect::new(nums[0], nums[1], nums[2], nums[3]))
            } else {
              raise @raden.InvalidInput("src must be [x, y, w, h]")
            }
          _ => raise @raden.InvalidInput("src must be array or null")
        }
        ctx.blit_image_rect(
          @raden.Rect::new(
            json_num(cmd, "x"),
            json_num(cmd, "y"),
            json_num(cmd, "w"),
            json_num(cmd, "h"),
          ),
          build_inline_image(get(cmd, "image").unwrap()),
          src_rect,
        )
      }
      "text" => {
        // テキスト描画 + シェーピング結果の記録。
        // draw は "fill" | "stroke" | "none" (none は shape のみ記録)。
        let kern = match get(cmd, "kern") {
          Some(True) | None => true
          Some(False) => false
          _ => raise @raden.InvalidInput("kern must be boolean")
        }
        let liga = match get(cmd, "liga") {
          Some(True) | None => true
          Some(False) => false
          _ => raise @raden.InvalidInput("liga must be boolean")
        }
        let clig = match get(cmd, "clig") {
          Some(True) | None => true
          Some(False) => false
          _ => raise @raden.InvalidInput("clig must be boolean")
        }
        let index = match get(cmd, "index") {
          Some(Number(n, ..)) => n.to_int()
          Some(_) => raise @raden.InvalidInput("index must be number")
          None => 0
        }
        let f = load_font(
          fonts_dir,
          json_str(cmd, "font"),
          index,
          json_num(cmd, "size"),
          kern,
          liga,
          clig,
        )
        let text = json_str(cmd, "text")
        shapes.push(shape_dump_json(f, text))
        match json_str(cmd, "draw") {
          "fill" =>
            @font.fill_text(
              ctx,
              json_num(cmd, "x"),
              json_num(cmd, "y"),
              f,
              text,
            )
          "stroke" =>
            @font.stroke_text(
              ctx,
              json_num(cmd, "x"),
              json_num(cmd, "y"),
              f,
              text,
            )
          "none" => ()
          other => raise @raden.InvalidInput("unknown text draw mode: \{other}")
        }
      }
      "scene" => {
        // 上流 example の scene 描画。w/h は fixture の画像寸法。
        // animation は t = frame / fps で決定する (実時間を使わない)。
        let name = @scenes.SceneName::parse(json_str(cmd, "name"))
        let frame = match get(cmd, "frame") {
          Some(Number(n, ..)) => n.to_int64()
          Some(_) => raise @raden.InvalidInput("frame must be number")
          None => 0L
        }
        let fps = match get(cmd, "fps") {
          Some(Number(n, ..)) => n.to_int64()
          Some(_) => raise @raden.InvalidInput("fps must be number")
          None => 60L
        }
        if fps <= 0L {
          raise @raden.InvalidInput("fps must be > 0")
        }
        let t = @scenes.animation_t(frame, fps)
        @scenes.render(
          ctx,
          name,
          img.width().to_double(),
          img.height().to_double(),
          t,
        )
      }
      other => raise @raden.InvalidInput("unknown command op: \{other}")
    }
  }
  ctx.end()
  (img, shapes)
}

///|
/// Image を canonical な premultiplied RGBA8 バイト列へ変換する。
/// oracle の canonical_bytes と同一の並び:
///   4bpp → LE u32 (0xAARRGGBB) を (R,G,B,A) へ分解
///   1bpp → alpha バイトを (0,0,0,A) へ分解
fn canonical_bytes(img : @raden.Image) -> Bytes {
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
      let dst = (y * w + x) * 4
      out[dst] = ((word >> 16) & 0xFF).to_byte()
      out[dst + 1] = ((word >> 8) & 0xFF).to_byte()
      out[dst + 2] = (word & 0xFF).to_byte()
      out[dst + 3] = ((word >> 24) & 0xFF).to_byte()
    }
  }
  Bytes::from_array(out[:])
}

///|
/// meta.json の Json を組み立てる。キー集合は oracle の Meta と完全一致させる
/// (comparator が deny_unknown_fields でデシリアライズするため)。
fn meta_json(
  fixture_id : String,
  img_w : Int32,
  img_h : Int32,
  stride : Int32,
  pixel_format : String,
  input_sha : String,
  output_sha : String,
  output_bytes : Int32,
  exit_code : Int32,
  shapes : Array[Json],
) -> Json {
  let toolchain = match @env.get_env_var("RADEN_CANDIDATE_TOOLCHAIN") {
    Some(v) => v
    None => "moonc unknown"
  }
  let build_target = match @env.get_env_var("RADEN_CANDIDATE_TARGET") {
    Some(v) => v
    None => "moonbit-native"
  }
  // oracle の Meta は `skip_serializing_if = "Vec::is_empty"` のため
  // shapes が空のときキー自体を省略する。こちらも同じ規則で出す。
  let fields : Map[String, Json] = {
    "schema": "raden.result.v1",
    "fixture_id": fixture_id,
    "generator": "moonbit-candidate",
    "width": img_w,
    "height": img_h,
    "stride": stride,
    "pixel_format": pixel_format,
    "channel_order": "rgba8-premultiplied",
    "input_sha256": input_sha,
    "output_sha256": output_sha,
    "output_bytes": output_bytes,
    "upstream_sha": upstream_sha,
    "oracle_version": "0.1.0",
    "toolchain": toolchain,
    "build_target": build_target,
    "exit_code": exit_code,
  }
  if shapes.length() > 0 {
    fields["shapes"] = Json(shapes)
  }
  Json(fields)
}

///|
/// fixture 1 件を実行し、成果物を out_dir へ書き出す。
/// 描画失敗時も exit_code=2 の meta を書いて後段の comparator が
/// `candidate_failed` として検出できるようにする (fail-closed)。
async fn generate_one(
  fixture_path : String,
  fixture_id : String,
  out_dir : String,
  fonts_dir : String,
) -> Unit {
  let fixture_data = @fs.read_file(fixture_path, sync_timestamp=false)
  let fixture_bytes = fixture_data.binary()
  let input_sha = @sha256.sha256_hex(fixture_bytes[:])
  let fixture = fixture_data.json()
  let w = json_num(fixture, "width").to_int()
  let h = json_num(fixture, "height").to_int()
  let pixel_format = json_str(fixture, "pixel_format")
  let meta_path = "\{out_dir}/\{fixture_id}.meta.json"
  let raw_path = "\{out_dir}/\{fixture_id}.raw"
  try {
    let (img, shapes) = run_fixture(fixture, fonts_dir)
    let raw = canonical_bytes(img)
    let output_sha = @sha256.sha256_hex(raw[:])
    @fs.write_file(raw_path, raw, create_mode=@fs.CreateOrTruncate)
    @fs.write_file(
      meta_path,
      meta_json(
        fixture_id,
        w,
        h,
        img.stride(),
        pixel_format,
        input_sha,
        output_sha,
        raw.length(),
        0,
        shapes,
      ).stringify(indent=2),
      create_mode=@fs.CreateOrTruncate,
    )
    println("generate \{fixture_id}: ok (\{raw.length()} bytes)")
  } catch {
    e => {
      // 失敗した fixture は meta のみを書き、raw は残さない。
      // raw が残っていると成功時との混同を招くため、存在すれば消す。
      if @fs.exists(raw_path) {
        @fs.remove(raw_path)
      }
      @fs.write_file(
        meta_path,
        meta_json(fixture_id, w, h, 0, pixel_format, input_sha, "", 0, 2, []).stringify(
          indent=2,
        ),
        create_mode=@fs.CreateOrTruncate,
      )
      println("generate \{fixture_id}: FAILED \{e}")
    }
  }
}

///|
/// fixture 1 件のベンチ結果を raden.bench.v1 形式の Json として返す。
/// cold run (初回実行) と warm run (N 回) を分離して記録する。
async fn bench_one(
  fixture_path : String,
  fixture_id : String,
  fonts_dir : String,
  frames : Int32,
) -> Json {
  let fixture_data = @fs.read_file(fixture_path, sync_timestamp=false)
  let input_sha = @sha256.sha256_hex(fixture_data.binary()[:])
  let fixture = fixture_data.json()
  let w = json_num(fixture, "width").to_int()
  let h = json_num(fixture, "height").to_int()
  // cold run: 初回実行 (キャッシュ初期化コストを含む)
  let t0 = @bench.monotonic_clock_start()
  let (img, _) = run_fixture(fixture, fonts_dir)
  // monotonic_clock_end はマイクロ秒を返す。oracle の ms 報告に合わせる。
  let cold_ms = @bench.monotonic_clock_end(t0) / 1000.0
  let sha = @sha256.sha256_hex(canonical_bytes(img)[:])
  // warm runs: 毎回 run_fixture 全体 (画像確保込み) を計測
  let times : Array[Double] = []
  for _ in 0..<frames {
    let t = @bench.monotonic_clock_start()
    let _ = run_fixture(fixture, fonts_dir)
    times.push(@bench.monotonic_clock_end(t) / 1000.0)
  }
  times.sort()
  let p50 = times[times.length() * 50 / 100]
  let p95 = times[times.length() * 95 / 100]
  let mut sum = 0.0
  for t in times {
    sum = sum + t
  }
  let mean = sum / times.length().to_double()
  {
    "fixture_id": fixture_id,
    "input_sha256": input_sha,
    "width": w,
    "height": h,
    "frames": frames,
    "cold_ms": cold_ms,
    "warm_p50_ms": p50,
    "warm_p95_ms": p95,
    "warm_mean_ms": mean,
    "output_sha256": sha,
  }
}

///|
async fn main {
  let args = @env.args()
  // 引数形式:
  //   <prog> generate --fixtures <dir> --out <dir> [--filter <id>] [--fonts <dir>]
  //   <prog> bench --fixtures <dir> [--filter <substr>] [--frames N] [--fonts <dir>] [--out <file>]
  guard args.length() >= 2 && (args[1] == "generate" || args[1] == "bench") else {
    println(
      "usage: moonbit-candidate generate --fixtures <dir> --out <dir> [--filter <id>] [--fonts <dir>]",
    )
    abort("invalid arguments")
  }
  if args[1] == "bench" {
    run_bench(args)
    return
  }
  let mut fixtures_dir = ""
  let mut out_dir = ""
  let mut fonts_dir = ""
  let mut filter : String? = None
  let mut i = 2
  while i < args.length() {
    match args[i] {
      "--fixtures" => {
        fixtures_dir = args[i + 1]
        i = i + 2
      }
      "--out" => {
        out_dir = args[i + 1]
        i = i + 2
      }
      "--filter" => {
        filter = Some(args[i + 1])
        i = i + 2
      }
      "--fonts" => {
        fonts_dir = args[i + 1]
        i = i + 2
      }
      other => abort("unknown argument: \{other}")
    }
  }
  guard fixtures_dir != "" && out_dir != "" else {
    abort("--fixtures and --out are required")
  }
  // --fonts 未指定時は fixtures の兄弟ディレクトリ fonts を使う
  if fonts_dir == "" {
    fonts_dir = "\{fixtures_dir}/../fonts"
  }
  @fs.mkdir(out_dir, recursive=true, allow_exist=true)
  let entries = @fs.readdir(fixtures_dir)
  entries.sort()
  for name in entries {
    guard name.has_suffix(".json") else { continue }
    let id = name[:name.length() - 5].to_owned()
    match filter {
      Some(f) if f != id => continue
      _ => ()
    }
    generate_one("\{fixtures_dir}/\{name}", id, out_dir, fonts_dir)
  }
}

///|
/// `--frames` の正の整数パース。不正値は実行を止める (fail-closed)。
fn parse_positive_int(s : String) -> Int32 {
  let mut n = 0
  if s.is_empty() {
    abort("invalid --frames")
  }
  for ch in s {
    if ch < '0' || ch > '9' {
      abort("invalid --frames")
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  if n <= 0 {
    abort("--frames must be > 0")
  }
  n
}

///|
/// `bench` サブコマンド: fixtures 内の全 fixture (--filter で部分一致絞り込み)
/// を測定し、raden.bench.v1 形式のレポートを書き出す。
async fn run_bench(args : ArrayView[String]) -> Unit {
  let mut fixtures_dir = ""
  let mut fonts_dir = ""
  let mut filter : String? = None
  let mut frames = 30
  let mut out : String? = None
  let mut i = 2
  while i < args.length() {
    match args[i] {
      "--fixtures" => {
        fixtures_dir = args[i + 1]
        i = i + 2
      }
      "--fonts" => {
        fonts_dir = args[i + 1]
        i = i + 2
      }
      "--filter" => {
        filter = Some(args[i + 1])
        i = i + 2
      }
      "--frames" => {
        frames = parse_positive_int(args[i + 1])
        i = i + 2
      }
      "--out" => {
        out = Some(args[i + 1])
        i = i + 2
      }
      other => abort("unknown argument: \{other}")
    }
  }
  guard fixtures_dir != "" else { abort("--fixtures is required") }
  if fonts_dir == "" {
    fonts_dir = "\{fixtures_dir}/../../fonts"
  }
  let entries = @fs.readdir(fixtures_dir)
  entries.sort()
  let results : Array[Json] = []
  for name in entries {
    guard name.has_suffix(".json") else { continue }
    let id = name[:name.length() - 5].to_owned()
    match filter {
      Some(f) if !id.contains(f) => continue
      _ => ()
    }
    let r = bench_one("\{fixtures_dir}/\{name}", id, fonts_dir, frames)
    println("bench \{id}: done")
    results.push(r)
  }
  let toolchain = match @env.get_env_var("RADEN_CANDIDATE_TOOLCHAIN") {
    Some(v) => v
    None => "moonc unknown"
  }
  let build_target = match @env.get_env_var("RADEN_CANDIDATE_TARGET") {
    Some(v) => v
    None => "moonbit-native"
  }
  let report : Json = {
    "schema": "raden.bench.v1",
    "generator": "moonbit-candidate",
    "upstream_sha": upstream_sha,
    "toolchain": toolchain,
    "build_target": build_target,
    "results": Json(results),
  }
  match out {
    Some(path) => {
      @fs.write_file(
        path,
        report.stringify(indent=2),
        create_mode=@fs.CreateOrTruncate,
      )
      println("wrote \{path}")
    }
    None => println(report.stringify(indent=2))
  }
}
