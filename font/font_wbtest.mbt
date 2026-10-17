/// 実フォント (Source Sans 3 Regular, vendored) を使った統合テスト。
/// native ターゲット専用 (ファイル I/O が async のため)。
///
/// 上流 tests/test_font.rs の Source Sans 3 系テストに相当。

///|
/// vendored フォントのパス (リポジトリルート基準の cwd からの相対)。
const FONT_PATH : String = "conformance/fonts/SourceSans3-Regular.ttf"

///|
async fn load_face() -> FontFace {
  let bytes = @fs.read_file(FONT_PATH, sync_timestamp=false).binary()
  let data = FontData::from_bytes(bytes)
  FontFace::from_data(data, 0)
}

///|
async fn load_font(size : Double) -> Font {
  Font::from_face(load_face(), size)
}

///|
async test "Source Sans 3: フェイスメトリクス" {
  let face = load_face()
  assert_eq(face.units_per_em(), 1000)
  assert_true(face.ascent() > 0)
  assert_true(face.descent() < 0)
  // Source Sans 3 は OS/2 v4 → cap/x height が存在する
  match face.cap_height() {
    Some(v) => assert_true(v > 0)
    None => fail("cap_height は Some(正値) である必要がある")
  }
  match face.x_height() {
    Some(v) => assert_true(v > 0)
    None => fail("x_height は Some(正値) である必要がある")
  }
}

///|
async test "Source Sans 3: cmap 文字→グリフマッピング" {
  let font = load_font(48.0)
  let glyph_a = font.map_char_to_glyph('A')
  assert_false(glyph_a == 0)
  let glyph_space = font.map_char_to_glyph(' ')
  assert_false(glyph_space == 0)
  assert_true(font.glyph_advance(glyph_a) > 0.0)
  assert_true(font.glyph_advance(glyph_space) > 0.0)
  // 存在しないコードポイントは .notdef (0)
  assert_eq(font.map_char_to_glyph('\u{10FFFE}'), 0)
}

///|
async test "Source Sans 3: shape ABC は 3 グリフ" {
  let font = load_font(48.0)
  let buffer = font.shape("ABC")
  assert_eq(buffer.length(), 3)
  for i = 0; i < buffer.length(); i = i + 1 {
    assert_false(
      buffer.glyph_id(i) == Some(0),
      msg="既知のラテン文字 \{i} は .notdef にならない必要がある",
    )
  }
}

///|
async test "Source Sans 3: liga 有効時 ff → f_f 合字" {
  let font = Font::with_features(
    load_face(),
    48.0,
    FontFeatureSettings::none().with_liga(true),
  )
  let buffer_ff = font.shape("ff")
  assert_eq(buffer_ff.length(), 1)
  assert_false(buffer_ff.glyph_id(0) == Some(0))
  // Source Sans 3 の 'liga' feature は f_f / f_f_t / f_t の Type 4 リガチャのみで、
  // ffi の文脈依存リガチャは Type 6 (ChainContextSubst) — raden 未対応のため
  // ffi → f_f + i の 2 グリフになる (上流と同じ)。
  let buffer_ffi = font.shape("ffi")
  assert_eq(buffer_ffi.length(), 2)
  for i = 0; i < buffer_ffi.length(); i = i + 1 {
    assert_false(buffer_ffi.glyph_id(i) == Some(0))
  }
}

///|
async test "Source Sans 3: liga 無効時 ffi は 3 グリフ" {
  let font = Font::with_features(load_face(), 48.0, FontFeatureSettings::none())
  let buffer = font.shape("ffi")
  assert_eq(buffer.length(), 3)
}

///|
async test "Source Sans 3: kern AV は advance を縮める" {
  let face = load_face()
  let font_no_kern = Font::with_features(
    face,
    48.0,
    FontFeatureSettings::none(),
  )
  let font_kern = Font::with_features(
    face,
    48.0,
    FontFeatureSettings::none().with_kern(true),
  )
  let no_kern = font_no_kern.measure_text("AV").advance
  let with_kern = font_kern.measure_text("AV").advance
  let kern_delta = no_kern - with_kern
  assert_true(
    kern_delta > 1.0e-6,
    msg="kern 有効時の AV advance (\{with_kern}) は無効時 (\{no_kern}) より小さい必要がある (delta = \{kern_delta})",
  )
}

///|
async test "Source Sans 3: clig 単独では panic せず liga は適用されない" {
  let face = load_face()
  // Source Sans 3 の 'clig' は Type 6 (未対応) で実装されているため
  // 結果は変化しないが、パース・適用経路が panic せず
  // well-formed な GlyphBuffer を返すことを検証する。
  let font_clig = Font::with_features(
    face,
    48.0,
    FontFeatureSettings::none().with_clig(true),
  )
  let buffer = font_clig.shape("ffi")
  assert_true(buffer.is_well_formed())
  assert_eq(buffer.length(), 3)
  let font_both = Font::with_features(
    face,
    48.0,
    FontFeatureSettings::none().with_liga(true).with_clig(true),
  )
  assert_eq(font_both.shape("ffi").length(), 2)
}

///|
async test "Source Sans 3: liga/kern の組み合わせ独立性" {
  let face = load_face()
  let combos : Array[(Bool, Bool)] = [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]
  let ffi_lens : Array[Int32] = []
  let av_advances : Array[Double] = []
  for c in combos {
    let (liga, kern) = c
    let font = Font::with_features(
      face,
      48.0,
      FontFeatureSettings::none().with_liga(liga).with_kern(kern),
    )
    ffi_lens.push(font.shape("ffi").length())
    av_advances.push(font.measure_text("AV").advance)
  }
  // liga ON のときだけ ff → f_f で 2 グリフ
  assert_eq(ffi_lens[0], 3)
  assert_eq(ffi_lens[1], 3)
  assert_eq(ffi_lens[2], 2)
  assert_eq(ffi_lens[3], 2)
  // kern ON は liga の有無に関わらず advance を縮める
  assert_true(av_advances[1] < av_advances[0])
  assert_true(av_advances[3] < av_advances[2])
}

///|
async test "Source Sans 3: measure_text の bearing 整合性" {
  let font = load_font(48.0)
  let text = "AB"
  let metrics = font.measure_text(text)
  let buffer = font.shape(text)
  let gid_a = font.map_char_to_glyph('A')
  let gid_b = font.map_char_to_glyph('B')
  guard font.glyph_bounds(gid_a) is Some(bbox_a) else {
    fail("A の glyph_bounds が必要")
  }
  guard font.glyph_bounds(gid_b) is Some(bbox_b) else {
    fail("B の glyph_bounds が必要")
  }
  let placement_a = buffer.placement(0).unwrap()
  let placement_b = buffer.placement(buffer.length() - 1).unwrap()
  assert_true(
    (metrics.leading_bearing - (bbox_a.x_min + placement_a.offset_x)).abs() <
    1.0e-9,
  )
  let expected_trailing = placement_b.advance -
    placement_b.offset_x -
    bbox_b.x_max
  assert_true((metrics.trailing_bearing - expected_trailing).abs() < 1.0e-9)
  // bounding_box はグリフ bbox の union
  match metrics.bounding_box {
    Some(bb) => {
      assert_true(bb.x_max > bb.x_min)
      assert_true(bb.y_max > bb.y_min)
    }
    None =>
      fail("非空文字列の bounding_box は Some である必要がある")
  }
}

///|
async test "Source Sans 3: shape_into のバッファ再利用" {
  let font = load_font(48.0)
  let buf = GlyphBuffer::new()
  font.shape_into("AB", buf)
  assert_false(buf.is_empty())
  font.shape_into("C", buf)
  assert_eq(buf.length(), 1)
  assert_false(buf.glyph_id(0) == Some(0))
}

///|
async test "Source Sans 3: with_features / set_feature_settings の等価性" {
  let face = load_face()
  let font_with = Font::with_features(face, 48.0, FontFeatureSettings::none())
  let font_set = Font::from_face(face, 48.0)
  font_set.set_feature_settings(FontFeatureSettings::none())
  assert_eq(font_with.size(), font_set.size())
  assert_eq(font_with.scale(), font_set.scale())
  let fs1 = font_with.feature_settings()
  let fs2 = font_set.feature_settings()
  assert_eq(fs1.kern, fs2.kern)
  assert_eq(fs1.liga, fs2.liga)
  assert_eq(fs1.clig, fs2.clig)
  assert_eq(font_with.shape("ff").length(), font_set.shape("ff").length())
}

///|
async test "Source Sans 3: 非 ASCII / 空文字列" {
  let font = load_font(48.0)
  // 空文字列
  let empty = font.shape("")
  assert_eq(empty.length(), 0)
  assert_true(empty.is_well_formed())
  let m = font.measure_text("")
  assert_eq(m.advance, 0.0)
  assert_true(m.bounding_box is None)
  // 非 ASCII (Source Sans 3 はラテン拡張を持つ)
  let b = font.shape("éü")
  assert_eq(b.length(), 2)
  // BMP 外 (サロゲートペア相当) — MoonBit String は UTF-16 で
  // for ch in text は Char (スカラー値) を返すため 1 文字 = 1 cluster。
  // 存在しないコードポイントは gid=0 (advance は継続する)。
  let emoji = font.shape("A😀B")
  assert_eq(emoji.length(), 3)
  // cluster は UTF-8 byte index (上流 char_indices 互換): A=1B, 😀=4B
  assert_eq(emoji.cluster(0), Some(0))
  assert_eq(emoji.cluster(1), Some(1))
  assert_eq(emoji.cluster(2), Some(5))
}

///|
async test "Source Sans 3: cluster は UTF-8 byte index" {
  // liga で ff → 1 グリフになっても cluster[0] は元の先頭文字 index を保持する。
  let buf = Font::with_features(
    load_face(),
    48.0,
    FontFeatureSettings::none().with_liga(true),
  ).shape("xffy")
  // x, f_f, y → cluster は 0, 1, 3 (f_f は 'f' の index=1 を保持)
  assert_eq(buf.length(), 3)
  assert_eq(buf.cluster(0), Some(0))
  assert_eq(buf.cluster(1), Some(1))
  assert_eq(buf.cluster(2), Some(3))
}

///|
async test "Source Sans 3: glyph_bounds / グリフアウトライン" {
  let font = load_font(48.0)
  let gid_a = font.map_char_to_glyph('A')
  guard font.glyph_bounds(gid_a) is Some(bb) else {
    fail("A の glyph_bounds が必要")
  }
  assert_true(bb.x_max > bb.x_min)
  assert_true(bb.y_max > bb.y_min)
  // append_glyph_outline で Path が非空になる
  let path = @raden.Path::new()
  font.append_glyph_outline(gid_a, 0.0, 100.0, path)
  assert_false(path.is_empty())
  guard path.bounding_box() is Some(pbb) else { fail("path bbox が必要") }
  assert_true(pbb.w > 0.0 && pbb.h > 0.0)
}

///|
async test "Source Sans 3: fill_text / stroke_text で描画される" {
  let font = load_font(48.0)
  let img = @raden.Image::new(400, 120, @raden.PixelFormat::Prgb32)
  let runtime = @raden.PipelineRuntime::new()
  let ctx = @raden.Context::new(img, runtime)
  ctx.set_fill_style(@raden.Rgba32::rgb(255, 255, 255))
  ctx.fill_rect(@raden.Rect::new(0.0, 0.0, 400.0, 120.0))
  ctx.set_fill_style(@raden.Rgba32::rgb(0, 0, 0))
  fill_text(ctx, 10.0, 60.0, font, "ffi AV fl")
  stroke_text(ctx, 10.0, 100.0, font, "ffi")
  // 黒ピクセルが存在すること (描画された)
  let mut dark = 0
  for i = 0; i < img.data().length() / 4; i = i + 1 {
    if img.data()[i * 4].to_int() < 128 {
      dark = dark + 1
    }
  }
  assert_true(
    dark > 500,
    msg="fill/stroke で十分な黒ピクセルが描画される必要がある (dark=\{dark})",
  )
}
