///|
/// Vector Playground の M2/M3 編集用 custom scene。
///
/// JS から渡された JSON spec に従い、Path・fill rule・matrix・clip・
/// paint・stroke・comp op・診断 overlay を組み合わせて 1 枚描く。
/// 参照画像は存在しないため、UI では NO REFERENCE と表示する。
///
/// spec schema (raden.playground-custom.v1):
/// {
///   "points": [x0,y0,x1,y1,x2,y2,x3,y3],
///   "fill_rule": "nonzero" | "evenodd",
///   "matrix": {"tx":0,"ty":0,"sx":1,"sy":1,"rotate":0},
///   "clip": null | {"x":0,"y":0,"w":512,"h":512},
///   "paint": {"kind":"solid","r":..,"g":..,"b":..,"a":..}
///          | {"kind":"linear","x0":..,"y0":..,"x1":..,"y1":..,
///             "stops":[{"offset":..,"r":..,"g":..,"b":..,"a":..}]},
///   "stroke": null | {"width":..,"cap":"butt|square|round",
///                     "join":"miter_clip|miter_bevel|miter_round|bevel|round",
///                     "dash":[..],"dash_offset":..},
///   "comp_op": "SrcOver" | ... ,
///   "overlay": "none" | "edges"
/// }

///|
fn cget(j : Json, key : String) -> Json? {
  if j is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

///|
fn cnum(j : Json, key : String, default : Double) -> Double {
  match cget(j, key) {
    Some(Number(n, ..)) => n
    _ => default
  }
}

///|
fn cstr(j : Json, key : String, default : String) -> String {
  match cget(j, key) {
    Some(String(s)) => s
    _ => default
  }
}

///|
fn carr(j : Json, key : String) -> Array[Json] {
  match cget(j, key) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
fn cobj(j : Json, key : String) -> Json? {
  match cget(j, key) {
    Some(Object(_) as o) => Some(o)
    _ => None
  }
}

///|
fn parse_comp_op(s : String) -> @raden.CompOp {
  match s {
    "SrcCopy" => @raden.SrcCopy
    "Multiply" => @raden.Multiply
    "Screen" => @raden.Screen
    "Xor" => @raden.Xor
    "Clear" => @raden.Clear
    "Plus" => @raden.Plus
    "Difference" => @raden.Difference
    _ => @raden.SrcOver
  }
}

///|
fn parse_fill_rule(s : String) -> @raden.FillRule {
  if s == "evenodd" {
    @raden.EvenOdd
  } else {
    @raden.NonZero
  }
}

///|
fn parse_cap(s : String) -> @raden.StrokeCap {
  match s {
    "square" => @raden.Square
    "round" => @raden.Round
    _ => @raden.Butt
  }
}

///|
fn parse_join(s : String) -> @raden.StrokeJoin {
  match s {
    "miter_bevel" => @raden.MiterBevel
    "miter_round" => @raden.MiterRound
    "bevel" => @raden.Bevel
    "round" => @raden.Round
    _ => @raden.MiterClip
  }
}

///|
fn points_from(j : Json) -> Array[Double] {
  // 512x512 の五芒星 (自己交差)。NonZero は中心も塗り、EvenOdd は穴になる。
  let mut pts : Array[Double] = [
    256.0, 66.0, 368.0, 410.0, 75.0, 197.0, 437.0, 197.0, 144.0, 410.0,
  ]
  let a = carr(j, "points")
  if a.length() >= 6 && a.length() % 2 == 0 {
    let parsed : Array[Double] = []
    for v in a {
      match v {
        Number(n, ..) => parsed.push(n)
        _ => parsed.push(0.0)
      }
    }
    pts = parsed
  }
  pts
}

///|
fn set_paint(ctx : @raden.Context, paint : Json) -> Unit {
  let kind = cstr(paint, "kind", "solid")
  if kind == "linear" {
    let g = @raden.Gradient::new_linear(
      cnum(paint, "x0", 0.0),
      cnum(paint, "y0", 0.0),
      cnum(paint, "x1", 512.0),
      cnum(paint, "y1", 512.0),
    )
    let stops = carr(paint, "stops")
    if stops.is_empty() {
      g.add_stop(0.0, @raden.Rgba32::new(255, 80, 40, 255)) |> ignore
      g.add_stop(1.0, @raden.Rgba32::new(40, 120, 255, 255)) |> ignore
    } else {
      for s in stops {
        g.add_stop(
          cnum(s, "offset", 0.0),
          @raden.Rgba32::new(
            cnum(s, "r", 255.0).to_uint(),
            cnum(s, "g", 255.0).to_uint(),
            cnum(s, "b", 255.0).to_uint(),
            cnum(s, "a", 255.0).to_uint(),
          ),
        )
        |> ignore
      }
    }
    ctx.set_fill_style_gradient(g)
  } else {
    ctx.set_fill_style(
      @raden.Rgba32::new(
        cnum(paint, "r", 80.0).to_uint(),
        cnum(paint, "g", 180.0).to_uint(),
        cnum(paint, "b", 255.0).to_uint(),
        cnum(paint, "a", 255.0).to_uint(),
      ),
    )
  }
}

///|
pub fn render_custom_rgba8(
  spec : String,
  w : Int32,
  h : Int32,
) -> Bytes raise @raden.RadenError {
  if w <= 0 || h <= 0 || w > 4096 || h > 4096 {
    raise @raden.InvalidInput("invalid custom size \{w}x\{h} (1..4096)")
  }
  let j = @json.parse(spec) catch {
    _ => raise @raden.InvalidInput("invalid custom spec JSON")
  }
  let pts = points_from(j)
  let img = @raden.Image::new(w, h, @raden.Prgb32)
  let ctx = @raden.Context::new(img, @raden.PipelineRuntime::new())

  // 背景 (比較用の固定色)
  ctx.set_comp_op(@raden.SrcCopy)
  ctx.set_fill_style(@raden.Rgba32::new(0x1A, 0x1E, 0x2C, 0xFF))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, w.to_double(), h.to_double()))

  ctx.set_comp_op(parse_comp_op(cstr(j, "comp_op", "SrcOver")))
  ctx.save()
  let m = cobj(j, "matrix")
  let (tx, ty, sx, sy, rot) = match m {
    Some(m) =>
      (
        cnum(m, "tx", 0.0),
        cnum(m, "ty", 0.0),
        cnum(m, "sx", 1.0),
        cnum(m, "sy", 1.0),
        cnum(m, "rotate", 0.0),
      )
    None => (0.0, 0.0, 1.0, 1.0, 0.0)
  }
  ctx.translate(tx, ty)
  ctx.rotate(rot * @math.PI / 180.0)
  ctx.scale(sx, sy)

  match cobj(j, "clip") {
    Some(c) =>
      ctx.clip_to_rect(
        @raden.Rect::new(
          cnum(c, "x", 0.0),
          cnum(c, "y", 0.0),
          cnum(c, "w", w.to_double()),
          cnum(c, "h", h.to_double()),
        ),
      )
    None => ()
  }

  let path = @raden.Path::new()
  let n = pts.length() / 2
  path.move_to(pts[0], pts[1])
  for i in 1..<n {
    path.line_to(pts[i * 2], pts[i * 2 + 1])
  }
  path.close()

  ctx.set_fill_rule(parse_fill_rule(cstr(j, "fill_rule", "nonzero")))
  match cobj(j, "paint") {
    Some(paint) => set_paint(ctx, paint)
    None => ctx.set_fill_style(@raden.Rgba32::new(80, 180, 255, 255))
  }
  ctx.fill_path(path)

  match cobj(j, "stroke") {
    Some(st) => {
      ctx.set_stroke_style(@raden.Rgba32::new(255, 255, 255, 220))
      ctx.set_stroke_width(cnum(st, "width", 6.0))
      ctx.set_stroke_cap(parse_cap(cstr(st, "cap", "butt")))
      ctx.set_stroke_join(parse_join(cstr(st, "join", "miter_clip")))
      let dash = carr(st, "dash")
      let dash_arr : Array[Double] = []
      for d in dash {
        match d {
          Number(n, ..) => dash_arr.push(n)
          _ => ()
        }
      }
      ctx.set_stroke_dash_array(dash_arr[:])
      ctx.set_stroke_dash_offset(cnum(st, "dash_offset", 0.0))
      ctx.stroke_path(path)
    }
    None => ()
  }

  if cstr(j, "overlay", "none") == "edges" {
    ctx.set_comp_op(@raden.SrcOver)
    ctx.set_stroke_style(@raden.Rgba32::new(255, 70, 70, 240))
    ctx.set_stroke_width(1.5)
    ctx.set_stroke_cap(@raden.Butt)
    ctx.set_stroke_join(@raden.MiterClip)
    ctx.set_stroke_dash_array([])
    ctx.stroke_path(path)
  }

  ctx.restore()
  ctx.end()
  @scenes.canonical_rgba8(img)
}
