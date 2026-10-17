///|
/// 公開 API (Image / Rgba32 / Context / geometry / Path) のテスト。
/// 描画結果は Image 内の LE u32 (0xAARRGGBB) を直接読んで検証する。
/// 数値の期待値は上流の整数式を手計算したものであり、
/// conformance では Rust oracle との完全一致で最終検証する。

///|
/// テスト用ヘルパ: (x, y) のピクセルを LE u32 として読む。4bpp 系専用。
fn px(img : Image, x : Int32, y : Int32) -> UInt32 {
  let d = img.data()
  let off = y * img.stride() + x * 4
  d[off].to_uint() |
  (d[off + 1].to_uint() << 8) |
  (d[off + 2].to_uint() << 16) |
  (d[off + 3].to_uint() << 24)
}

///|
/// テスト用ヘルパ: Context を付けた Image を作る。
fn new_ctx(w : Int32, h : Int32) -> (Image, Context) raise {
  let img = Image::new(w, h, Prgb32)
  (img, Context::new(img, PipelineRuntime::new()))
}

///|
test "Rgba32 の基本操作" {
  let c = Rgba32::new(255, 128, 64, 255)
  assert_eq(c.r(), 255)
  assert_eq(c.g(), 128)
  assert_eq(c.b(), 64)
  assert_eq(c.a(), 255)
  assert_eq(c.is_opaque(), true)
  assert_eq(c.is_transparent(), false)
  // straight → premultiplied: (c*a+128)/255
  assert_eq(Rgba32::new(255, 128, 0, 128).to_prgb32(), 0x80804000)
  assert_eq(Rgba32::rgb(1, 2, 3).a(), 255)
}

///|
test "Image::new の入力検証" {
  // 負の寸法は InvalidInput。
  try Image::new(-1, 10, Prgb32) catch {
    e =>
      inspect(
        e,
        content="InvalidInput(Image::new: negative dimensions (width=-1, height=10))",
      )
  } noraise {
    _ => fail("expected Image::new to raise")
  }
  // 上限超過は ResourceLimit。
  try Image::new(40000, 40000, Prgb32) catch {
    e => inspect(e is ResourceLimit(_), content="true")
  } noraise {
    _ => fail("expected Image::new to raise")
  }
  // 0 寸法は許容 (上流と同じく空バッファ)。
  let zero = Image::new(0, 0, Prgb32)
  assert_eq(zero.width(), 0)
  assert_eq(zero.data().length(), 0)
}

///|
test "Image::from_rgba8 は straight を premultiplied へ変換する" {
  let rgba8 : Bytes = [255, 0, 0, 128, 0, 255, 0, 255]
  let img = Image::from_rgba8(2, 1, Prgb32, rgba8[:])
  // (255,0,0,128) → a=128, r=(255*128+128)/255=128 → 0x80800000
  assert_eq(px(img, 0, 0), 0x80800000)
  // (0,255,0,255) → 0xFF00FF00
  assert_eq(px(img, 1, 0), 0xFF00FF00)
  // 長さ不一致は InvalidInput。
  let short : Bytes = b"\x00"
  try Image::from_rgba8(2, 1, Prgb32, short[:]) catch {
    e => inspect(e is InvalidInput(_), content="true")
  } noraise {
    _ => fail("expected Image::from_rgba8 to raise")
  }
}

///|
test "Context fill_rect SrcCopy" {
  let (img, ctx) = new_ctx(4, 4)
  ctx.set_comp_op(SrcCopy)
  ctx.set_fill_style(Rgba32::new(255, 0, 0, 255))
  ctx.fill_rect(Rect::new(1.0, 1.0, 2.0, 2.0))
  assert_eq(px(img, 1, 1), 0xFFFF0000)
  assert_eq(px(img, 2, 2), 0xFFFF0000)
  // 矩形の外側は無変更。
  assert_eq(px(img, 0, 0), 0)
  assert_eq(px(img, 3, 3), 0)
}

///|
test "Context fill_rect SrcOver 半透明" {
  let (img, ctx) = new_ctx(2, 2)
  // 不透明の下地。
  ctx.set_comp_op(SrcCopy)
  ctx.set_fill_style(Rgba32::new(255, 0, 0, 255))
  ctx.fill_all()
  // a=128 の緑を SrcOver。premult g=(255*128+128)/255=128 → src=0x80008000。
  // inv=128 → out_g = 128 + (0*128>>8) = 128, out_r = 0 + (255*128>>8) = 127,
  // out_a = 128 + (255*128>>8) = 255。
  ctx.set_comp_op(SrcOver)
  ctx.set_fill_style(Rgba32::new(0, 255, 0, 128))
  ctx.fill_rect(Rect::new(0.0, 0.0, 2.0, 2.0))
  assert_eq(px(img, 0, 0), 0xFF7F8000)
}

///|
test "Context clear_rect と clear_all" {
  let (img, ctx) = new_ctx(4, 4)
  ctx.set_fill_style(Rgba32::new(1, 2, 3, 4))
  ctx.fill_all()
  ctx.clear_rect(Rect::new(0.0, 0.0, 2.0, 2.0))
  assert_eq(px(img, 0, 0), 0)
  assert_eq(px(img, 1, 1), 0)
  // clear_rect 範囲外は残る。
  assert_eq(px(img, 3, 3) != 0, true)
  ctx.clear_all()
  assert_eq(px(img, 3, 3), 0)
}

///|
test "clip_to_rect で描画範囲を制限する" {
  let (img, ctx) = new_ctx(4, 4)
  ctx.clip_to_rect(Rect::new(1.0, 1.0, 2.0, 2.0))
  ctx.set_comp_op(SrcCopy)
  ctx.set_fill_style(Rgba32::new(255, 255, 255, 255))
  ctx.fill_all()
  assert_eq(px(img, 1, 1), 0xFFFFFFFF)
  assert_eq(px(img, 0, 0), 0)
  assert_eq(px(img, 3, 3), 0)
  // restore_clipping でメタクリップへ戻る。
  ctx.restore_clipping()
  ctx.clear_all()
  ctx.fill_all()
  assert_eq(px(img, 3, 3), 0xFFFFFFFF)
}

///|
test "translate は描画座標を移動する" {
  let (img, ctx) = new_ctx(4, 4)
  ctx.set_comp_op(SrcCopy)
  ctx.set_fill_style(Rgba32::new(255, 0, 0, 255))
  ctx.translate(1.0, 2.0)
  ctx.fill_rect(Rect::new(0.0, 0.0, 1.0, 1.0))
  // (0,0,1,1) + (1,2) → (1,2) のピクセルのみ。
  assert_eq(px(img, 1, 2), 0xFFFF0000)
  assert_eq(px(img, 0, 0), 0)
}

///|
test "save/restore で状態を復元する" {
  let (img, ctx) = new_ctx(2, 2)
  ctx.set_fill_style(Rgba32::new(255, 0, 0, 255))
  ctx.save()
  ctx.set_fill_style(Rgba32::new(0, 255, 0, 255))
  ctx.restore()
  ctx.set_comp_op(SrcCopy)
  ctx.fill_all()
  assert_eq(px(img, 0, 0), 0xFFFF0000)
}

///|
test "global_alpha と fill_alpha は塗りに効く" {
  let (img, ctx) = new_ctx(2, 2)
  ctx.set_comp_op(SrcCopy)
  ctx.set_fill_style(Rgba32::new(255, 0, 0, 255))
  ctx.set_fill_alpha(0.5)
  ctx.fill_all()
  // fill alpha 128 → premult r=(255*128+128)/255=128。
  assert_eq(px(img, 0, 0), 0x80800000)
}

///|
test "Matrix2D の基本演算" {
  let id = Matrix2D::identity()
  assert_eq(id.is_identity(), true)
  // 平行移動 + 拡大: T(1,2) * S(2,3) の合成順序。
  // 上流の multiply は self * other で、点へは self が先に適用される
  // (p·(T·S) = (p·T)·S)。(1,1) → T → (2,3) → S → (4,9)。
  let m = Matrix2D::translation(1.0, 2.0).multiply(Matrix2D::scaling(2.0, 3.0))
  let (x, y) = m.map_point(1.0, 1.0)
  assert_eq(x, 4.0)
  assert_eq(y, 9.0)
  // 逆行列で元の点に戻る。
  match m.invert() {
    Some(inv) => {
      let (x2, y2) = inv.map_point(x, y)
      assert_eq(
        (x2 - 1.0).abs() < 0.0000001 && (y2 - 1.0).abs() < 0.0000001,
        true,
      )
    }
    None => abort("invert failed")
  }
  // 特異行列は None。
  inspect(
    Matrix2D::new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0).invert() is None,
    content="true",
  )
}

///|
test "Path の構築と平坦化" {
  let p = Path::new()
  p.move_to(0.0, 0.0)
  p.line_to(10.0, 0.0)
  p.line_to(10.0, 10.0)
  p.close()
  assert_eq(p.is_empty(), false)
  // 平坦化: 線分 2 + close 1 = 3 エッジ。
  let edges : Array[Edge] = []
  flatten_path(p, edges)
  assert_eq(edges.length(), 3)
  // cubic は分割されて複数エッジになる。
  let p2 = Path::new()
  p2.move_to(0.0, 0.0)
  p2.cubic_to(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
  let edges2 : Array[Edge] = []
  flatten_path(p2, edges2)
  assert_eq(edges2.length() > 1, true)
  // 非有限座標は InvalidInput。
  let p3 = Path::new()
  p3.move_to(@double.not_a_number, 0.0)
  try flatten_path(p3, edges2) catch {
    e =>
      inspect(e, content="InvalidInput(path contains non-finite coordinates)")
  } noraise {
    _ => fail("expected flatten_path to raise")
  }
}

///|
test "Path::transform で座標を更新する" {
  let p = Path::new()
  p.move_to(1.0, 1.0)
  p.transform(Matrix2D::translation(10.0, 20.0))
  assert_eq(p.points()[0].x, 11.0)
  assert_eq(p.points()[0].y, 21.0)
}

///|
test "stroke_path はストロークを塗りつぶしパスに変換して描画する" {
  let img = Image::new(16, 16, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  ctx.set_comp_op(SrcCopy)
  ctx.set_stroke_style(Rgba32::new(255, 0, 0, 255))
  ctx.set_stroke_width(2.0)
  // 水平線のストローク。幅 2 なら上下 1 ピクセルずつ塗られる。
  let p = Path::new()
  p.move_to(2.0, 8.0)
  p.line_to(14.0, 8.0)
  ctx.stroke_path(p)
  // 中心ピクセルは不透明赤になっているはず。
  let px = img.read_u32((8 * 16 + 8) * 4)
  inspect(px, content="4294901760")
  // 幅が 0 以下なら何も描かれない (上流の早期 return と同じ)。
  let img2 = Image::new(4, 4, Prgb32) catch { e => fail("\{e}") }
  let ctx2 = Context::new(img2, PipelineRuntime::new())
  ctx2.set_comp_op(SrcCopy)
  ctx2.set_stroke_style(Rgba32::new(255, 0, 0, 255))
  ctx2.set_stroke_width(0.0)
  ctx2.stroke_path(p)
  inspect(img2.read_u32(0), content="0")
}

///|
test "stroke_path は失敗時にも fill 状態を復元する" {
  // A8 宛先では fill_path が UnsupportedFeature になる。
  // stroke_path は内部で fill 状態を一時差し替えするため、
  // エラー送出後も fill_color_prgb32 / fill_alpha が戻っていることを確認する。
  let img = Image::new(8, 8, A8) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  ctx.set_comp_op(SrcCopy)
  ctx.set_fill_style(Rgba32::new(10, 20, 30, 40))
  ctx.set_fill_alpha(0.5)
  ctx.set_stroke_style(Rgba32::new(255, 0, 0, 255))
  ctx.set_stroke_width(2.0)
  let p = Path::new()
  p.move_to(1.0, 4.0)
  p.line_to(7.0, 4.0)
  try ctx.stroke_path(p) catch {
    e =>
      inspect(
        e,
        content="UnsupportedFeature(fill_path is not supported for A8 destination)",
      )
  } noraise {
    _ => fail("expected stroke_path to raise")
  }
  // 一時差し替えした fill 状態が復元されている。
  // premultiply 済みの値 (10,20,30,a=40 → 0x28020305) が復元されている。
  inspect(ctx.fill_color_prgb32(), content="671220485")
  inspect(ctx.fill_alpha(), content="0.5")
}

///|
test "stroke_to_fill の輪郭生成: 空パスと退化パス" {
  let out = Path::new()
  // 空パスは何も出力しない。
  stroke_to_fill(Path::new(), 2.0, Butt, Butt, MiterClip, 4.0, [][:], 0.0, out)
  assert_eq(out.is_empty(), true)
  // 点のみ (線分なし) のパスも何も出力しない。
  let dot = Path::new()
  dot.move_to(3.0, 3.0)
  stroke_to_fill(dot, 2.0, Butt, Butt, MiterClip, 4.0, [][:], 0.0, out)
  assert_eq(out.is_empty(), true)
  // 通常の 1 線分は 1 つの閉じたコンターを作る。
  let line = Path::new()
  line.move_to(0.0, 0.0)
  line.line_to(10.0, 0.0)
  stroke_to_fill(line, 2.0, Butt, Butt, MiterClip, 4.0, [][:], 0.0, out)
  assert_eq(out.is_empty(), false)
}

///|
test "generate_lut: 停止点の補間と端のクランプ" {
  // 2 停止点の赤→青グラデーション。LUT 両端は停止色に一致する。
  let g = Gradient::new_linear(0.0, 0.0, 10.0, 0.0)
  g.add_stop(0.0, Rgba32::new(255, 0, 0, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 0, 255, 255)) |> ignore
  let lut = generate_lut(g.stops)
  inspect(lut[0], content="4294901760") // 0xFFFF0000
  inspect(lut[255], content="4278190335") // 0xFF0000FF
  // 中点は premultiplied 空間の 8.8 固定小数点補間。
  // t=128/255, t_fixed=(t*256) as u32=128, inv_t=128
  // → r=(255*128)>>8=127, b=(255*128)>>8=127。
  inspect(lut[128], content="4286513279") // a=255, r=127, b=127
  // 停止点なしなら全透明。
  let g0 = Gradient::new_linear(0.0, 0.0, 10.0, 0.0)
  let lut0 = generate_lut(g0.stops)
  inspect(lut0[100], content="0")
  // 1 停止点なら単色で埋まる。
  let g1 = Gradient::new_linear(0.0, 0.0, 10.0, 0.0)
  g1.add_stop(0.3, Rgba32::new(10, 200, 30, 128)) |> ignore
  let lut1 = generate_lut(g1.stops)
  // premultiply(10,200,30,128): r=(10*128+128)/255=5, g=(200*128+128)/255=100, b=(30*128+128)/255=15
  inspect(lut1[0], content="2147836943") // 0x8005640F
}

///|
test "add_stop は offset をクランプして昇順ソートする" {
  let g = Gradient::new_linear(0.0, 0.0, 1.0, 0.0)
  // 逆順で追加し、範囲外 offset を混ぜる。
  g.add_stop(0.7, Rgba32::new(70, 0, 0, 255)) |> ignore
  g.add_stop(-0.5, Rgba32::new(10, 0, 0, 255)) |> ignore // → 0.0
  g.add_stop(1.5, Rgba32::new(90, 0, 0, 255)) |> ignore // → 1.0
  g.add_stop(0.3, Rgba32::new(30, 0, 0, 255)) |> ignore
  let offs = g.stops().to_owned().map(fn(s) { s.offset })
  inspect(offs, content="[0, 0.3, 0.7, 1]")
}

///|
test "fill_rect のグラデーションは comp_op を参照しない" {
  // 上流の仕様: グラデーションの fill_rect は comp_op を無視し、
  // 不透明 LUT は直接ストア、半透明 LUT は SrcOver で合成する。
  // DstCopy を指定しても描画されることを確認する。
  let img = Image::new(8, 4, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  ctx.set_fill_style(Rgba32::new(9, 9, 9, 255))
  ctx.fill_rect(Rect::new(0.0, 0.0, 8.0, 4.0))
  let g = Gradient::new_linear(0.0, 0.0, 8.0, 0.0)
  g.add_stop(0.0, Rgba32::new(255, 0, 0, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 0, 255, 255)) |> ignore
  ctx.set_fill_style_gradient(g)
  ctx.set_comp_op(DstCopy)
  ctx.fill_rect(Rect::new(0.0, 0.0, 8.0, 4.0))
  // DstCopy なのに書き換わっている。
  // 先頭ピクセルは t≈0.0625 で idx=15 → lut[15] = 0xFFF0000E。
  inspect(img.read_u32(0), content="4293918734")
}

///|
test "パターン fill_rect は非対応 comp_op で UnsupportedFeature" {
  let img = Image::new(8, 8, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  let src = Image::new(4, 4, Prgb32) catch { e => fail("\{e}") }
  let pattern = Pattern::from_image(src) catch { e => fail("\{e}") }
  ctx.set_fill_style_pattern(pattern)
  ctx.set_comp_op(Multiply)
  try ctx.fill_rect(Rect::new(0.0, 0.0, 8.0, 8.0)) catch {
    e =>
      inspect(
        e,
        content="UnsupportedFeature(CompOp Multiply is not supported for pattern fill_rect; use SrcOver, SrcCopy, or fill_path)",
      )
  } noraise {
    _ => fail("expected fill_rect to raise")
  }
  // 例外でも画像は一切書き換わっていない (部分書き込みなし)。
  inspect(img.read_u32(0), content="0")
}

///|
test "set_fill_style は gradient/pattern を解除する" {
  let img = Image::new(4, 4, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  let g = Gradient::new_linear(0.0, 0.0, 4.0, 0.0)
  g.add_stop(0.0, Rgba32::new(255, 0, 0, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 0, 255, 255)) |> ignore
  ctx.set_fill_style_gradient(g)
  assert_eq(ctx.fill_gradient() is Some(_), true)
  // 単色に戻すとグラデーションが解除される。
  ctx.set_fill_style(Rgba32::new(0, 255, 0, 255))
  assert_eq(ctx.fill_gradient() is None, true)
  assert_eq(ctx.fill_pattern() is None, true)
  ctx.fill_rect(Rect::new(0.0, 0.0, 4.0, 4.0))
  inspect(img.read_u32(0), content="4278255360") // 0xFF00FF00
}

///|
test "save/restore は gradient/pattern スタイルを保存復元する" {
  let img = Image::new(4, 4, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  let g = Gradient::new_linear(0.0, 0.0, 4.0, 0.0)
  g.add_stop(0.0, Rgba32::new(255, 0, 0, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 0, 255, 255)) |> ignore
  ctx.set_fill_style_gradient(g)
  ctx.save()
  // セーブ後に単色へ変更しても restore でグラデーションが戻る。
  ctx.set_fill_style(Rgba32::new(0, 255, 0, 255))
  assert_eq(ctx.fill_gradient() is None, true)
  ctx.restore()
  assert_eq(ctx.fill_gradient() is Some(_), true)
}

///|
test "グラデーションを設定した Gradient の後続変更は描画に影響しない" {
  // set_fill_style_gradient はスナップショットを保持する (上流の clone() 相当)。
  let img = Image::new(8, 4, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  let g = Gradient::new_linear(0.0, 0.0, 8.0, 0.0)
  g.add_stop(0.0, Rgba32::new(255, 0, 0, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 0, 255, 255)) |> ignore
  ctx.set_fill_style_gradient(g)
  // 設定後に停止点を追加しても、保持済みスナップショットは変わらない。
  g.add_stop(0.5, Rgba32::new(0, 255, 0, 255)) |> ignore
  ctx.fill_rect(Rect::new(0.0, 0.0, 8.0, 4.0))
  // x=4 のピクセルは 2 停止版の中間色のまま (緑が混ざっていない)。
  // t≈0.5625 で idx=143 → lut[143] = 0xFF70008E。
  let px = img.read_u32(4 * 4)
  inspect(px, content="4285530254") // a=255 r=112 b=142
}

///|
test "A8 宛先のグラデーション fill_rect は UnsupportedFeature" {
  let img = Image::new(8, 4, A8) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  let g = Gradient::new_linear(0.0, 0.0, 8.0, 0.0)
  g.add_stop(0.0, Rgba32::new(255, 255, 255, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 0, 0, 255)) |> ignore
  ctx.set_fill_style_gradient(g)
  try ctx.fill_rect(Rect::new(0.0, 0.0, 8.0, 4.0)) catch {
    e =>
      inspect(
        e,
        content="UnsupportedFeature(pattern and gradient fills are not supported for A8 destination)",
      )
  } noraise {
    _ => fail("expected fill_rect to raise")
  }
}

///|
test "ソース == 宛先の blit はスナップショット経由で安全に転送される" {
  // 上流では借用規則により表現不能なエイリアス転送。
  // MoonBit では同一 Image を渡せるため、スナップショットして
  // 読み込みが書き込みに汚染されないことを検証する。
  let img = Image::new(8, 4, Prgb32) catch { e => fail("\{e}") }
  // 先に背景を単色で埋める (赤不透明)。
  {
    let ctx0 = Context::new(img, PipelineRuntime::new())
    ctx0.set_fill_style(Rgba32::new(200, 0, 0, 255))
    ctx0.fill_all()
  }
  let ctx = Context::new(img, PipelineRuntime::new())
  // 自身を (2, 0) へずらして転送。SrcCopy なら全ピクセルが
  // 「転送時点」の赤で上書きされ、移動先も赤のままになる。
  ctx.blit_image_at(2.0, 0.0, img) catch {
    e => fail("\{e}")
  }
  let d = img.data()
  // 転送範囲内 (2..8, 0..4) が全て元の赤 (0xFF0000C8) なら
  // スナップショットが機能している。
  for y in 0..<4 {
    for x in 2..<8 {
      let off = (y * 8 + x) * 4
      let px = d[off].to_uint() |
        (d[off + 1].to_uint() << 8) |
        (d[off + 2].to_uint() << 16) |
        (d[off + 3].to_uint() << 24)
      inspect(px, content="4291297280")
    }
  }
}

///|
test "グラデーション設定後の元オブジェクト変更は描画に影響しない" {
  // set_fill_style_gradient はスナップショットを保持する。
  // 設定後に元の Gradient を書き換えても LUT が再生成されず、
  // 古い停止点が返ってこないことを確認する。
  let img = Image::new(8, 2, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  let g = Gradient::new_linear(0.0, 0.0, 8.0, 0.0)
  g.add_stop(0.0, Rgba32::new(255, 0, 0, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 0, 255, 255)) |> ignore
  ctx.set_fill_style_gradient(g)
  // 設定後に元を書き換える (全緑)。
  g.add_stop(0.0, Rgba32::new(0, 255, 0, 255)) |> ignore
  g.add_stop(1.0, Rgba32::new(0, 255, 0, 255)) |> ignore
  ctx.fill_rect(Rect::new(0.0, 0.0, 8.0, 2.0))
  let d = img.data()
  let px = d[0].to_uint() |
    (d[1].to_uint() << 8) |
    (d[2].to_uint() << 16) |
    (d[3].to_uint() << 24)
  // 左端は元の停止点の赤を保持し、緑化していない。
  inspect(px, content="4293918734")
}

///|
test "パターン設定後の元画像変更は描画に影響しない" {
  // Pattern::new は画像バイトをスナップショットする。
  let tile = Image::new(2, 2, Prgb32) catch { e => fail("\{e}") }
  {
    let c = Context::new(tile, PipelineRuntime::new())
    c.set_fill_style(Rgba32::new(255, 0, 0, 255))
    c.fill_all()
  }
  let pat = Pattern::from_image(tile) catch { e => fail("\{e}") }
  // パターン生成後に元画像を緑へ塗り替える。
  {
    let c = Context::new(tile, PipelineRuntime::new())
    c.set_fill_style(Rgba32::new(0, 255, 0, 255))
    c.fill_all()
  }
  let img = Image::new(4, 2, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  ctx.set_fill_style_pattern(pat)
  ctx.fill_rect(Rect::new(0.0, 0.0, 4.0, 2.0))
  let d = img.data()
  let px = d[0].to_uint() |
    (d[1].to_uint() << 8) |
    (d[2].to_uint() << 16) |
    (d[3].to_uint() << 24)
  // 緑化していない (元の赤が残る)。
  inspect(px, content="4294901760")
}

///|
test "パターン fill_rect は SrcCopy/SrcOver 以外で UnsupportedFeature" {
  // 上流の assert に相当する入力検証。空でない矩形に対してのみ発火する。
  let tile = Image::new(2, 2, Prgb32) catch { e => fail("\{e}") }
  {
    let c = Context::new(tile, PipelineRuntime::new())
    c.set_fill_style(Rgba32::new(255, 0, 0, 255))
    c.fill_all()
  }
  let img = Image::new(4, 4, Prgb32) catch { e => fail("\{e}") }
  let ctx = Context::new(img, PipelineRuntime::new())
  let pat = Pattern::from_image(tile) catch { e => fail("\{e}") }
  ctx.set_fill_style_pattern(pat)
  ctx.set_comp_op(Multiply)
  // 非空矩形 → エラー。
  try ctx.fill_rect(Rect::new(0.0, 0.0, 4.0, 4.0)) catch {
    e =>
      inspect(
        e,
        content="UnsupportedFeature(CompOp Multiply is not supported for pattern fill_rect; use SrcOver, SrcCopy, or fill_path)",
      )
  } noraise {
    _ => fail("expected UnsupportedFeature")
  }
  // 空矩形 → 上流同様チェックを通過して早期 return (エラーなし)。
  ctx.fill_rect(Rect::new(0.0, 0.0, 0.0, 4.0)) catch {
    e => fail("empty rect should not raise: \{e}")
  }
}
