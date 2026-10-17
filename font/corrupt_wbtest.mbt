/// 破損フォント / 異常入力の耐性テスト。
/// フォントバイトは合成 (両ターゲット共通、fs 不要)。
///
/// 上流 raden はネットワーク取得した実フォントを mutate して検証しているが、
/// ここでは最小限の TTF を直接構築し、各防御チェックが
/// FontError::InvalidData で安全に失敗することを確認する。
/// (panic や無限ループではなく、明示エラーで終了することが要件)

///|
/// big-endian u16 → 2 バイト。
fn enc16(v : Int32) -> Bytes {
  Bytes::from_array([(v >> 8).to_byte(), v.to_byte()])
}

///|
/// big-endian u32 → 4 バイト。
fn enc32(v : Int32) -> Bytes {
  Bytes::from_array([
    (v >> 24).to_byte(),
    (v >> 16).to_byte(),
    (v >> 8).to_byte(),
    v.to_byte(),
  ])
}

///|
/// (tag, 内容) の配列から sfnt フォントバイトを組み立てる。
/// checksum は上流同様パース側で検証しないため 0 固定とする。
fn build_font(tables : Array[(Int32, Bytes)]) -> Bytes {
  let num_tables = tables.length()
  let dir_size = 12 + num_tables * 16
  // テーブルデータのオフセットを決定 (4 バイトアラインなし — パーサはアラインを要求しない)
  let parts : Array[Byte] = []
  let mut offset = dir_size
  let out : Array[Byte] = []
  // sfnt ヘッダ: version=0x00010000, numTables, searchRange 等は未検証なので 0
  for b in enc32(0x00010000) {
    out.push(b)
  }
  for b in enc16(num_tables) {
    out.push(b)
  }
  for _i = 0; _i < 6; _i = _i + 1 {
    out.push(0)
  }
  for t in tables {
    let (tag, body) = t
    // record: tag(4) + checksum(4)=0 + offset(4) + length(4)
    for b in enc32(tag) {
      out.push(b)
    }
    for _i = 0; _i < 4; _i = _i + 1 {
      out.push(0)
    }
    for b in enc32(offset) {
      out.push(b)
    }
    for b in enc32(body.length()) {
      out.push(b)
    }
    offset = offset + body.length()
    for b in body {
      parts.push(b)
    }
  }
  for b in parts {
    out.push(b)
  }
  Bytes::from_array(out)
}

///|
/// head テーブル (54 バイト)。units_per_em と indexToLocFormat のみ意味を持つ。
fn head_table(units_per_em : Int32, loc_format : Int32) -> Bytes {
  let b = FixedArray::make(54, (0 : Byte))
  b[18] = (units_per_em >> 8).to_byte()
  b[19] = units_per_em.to_byte()
  b[50] = (loc_format >> 8).to_byte()
  b[51] = loc_format.to_byte()
  Bytes::from_array(b[:])
}

///|
/// maxp テーブル (6 バイト): version(4) + numGlyphs(2)。
fn maxp_table(num_glyphs : Int32) -> Bytes {
  let b = FixedArray::make(6, (0 : Byte))
  b[4] = (num_glyphs >> 8).to_byte()
  b[5] = num_glyphs.to_byte()
  Bytes::from_array(b[:])
}

///|
/// hhea テーブル (36 バイト): ascent/descent/lineGap + numberOfHMetrics。
fn hhea_table(ascent : Int32, descent : Int32, num_h_metrics : Int32) -> Bytes {
  let b = FixedArray::make(36, (0 : Byte))
  b[4] = (ascent >> 8).to_byte()
  b[5] = ascent.to_byte()
  b[6] = (descent >> 8).to_byte()
  b[7] = descent.to_byte()
  b[34] = (num_h_metrics >> 8).to_byte()
  b[35] = num_h_metrics.to_byte()
  Bytes::from_array(b[:])
}

///|
/// hmtx テーブル: 全グリフ同一 advance=500, lsb=0。
fn hmtx_table(num_glyphs : Int32) -> Bytes {
  let b = FixedArray::make(num_glyphs * 4, (0 : Byte))
  for i = 0; i < num_glyphs; i = i + 1 {
    b[i * 4] = 1 // 500 >> 8
    b[i * 4 + 1] = 244 // 500 & 0xff
  }
  Bytes::from_array(b[:])
}

///|
/// 最小 cmap: format 4 で全文字を .notdef (0) にマップする
/// (終端セグメントのみ、idDelta=0)。
fn cmap_empty_format4() -> Bytes {
  // cmap header: version(2)=0, numTables(2)=1
  // encoding record: platform(2)=3, encoding(2)=1, offset(4)=12
  // format4 subtable: format(2)=4, length(2), language(2)=0,
  //   segCountX2(2)=2, searchRange(2)=2, entrySelector(2)=0, rangeShift(2)=0
  //   endCodes(2)=0xFFFF, reservedPad(2)=0, startCodes(2)=0xFFFF,
  //   idDeltas(2)=0, idRangeOffsets(2)=0 → 計 24 バイト
  let sub = FixedArray::make(24, (0 : Byte))
  sub[0] = 0
  sub[1] = 4 // format
  sub[2] = 0
  sub[3] = 24 // length
  sub[6] = 0
  sub[7] = 2 // segCountX2 = 2 (1 segment)
  sub[8] = 0
  sub[9] = 2 // searchRange
  sub[14] = 0xFF // endCode[0] = 0xFFFF
  sub[15] = 0xFF
  sub[16] = 0 // reservedPad
  sub[18] = 0xFF // startCode[0] = 0xFFFF
  sub[19] = 0xFF
  // idDelta=0, idRangeOffset=0
  let hdr = FixedArray::make(12, (0 : Byte))
  hdr[3] = 1 // numTables
  hdr[5] = 3 // platformID=3
  hdr[7] = 1 // encodingID=1
  hdr[11] = 12 // subtable offset
  let out : Array[Byte] = []
  for b in hdr {
    out.push(b)
  }
  for b in sub {
    out.push(b)
  }
  Bytes::from_array(out)
}

///|
/// num_glyphs 個の glyf データ片と loca (long format) を組み立てる。
/// 空配列要素は空グリフ。
fn glyf_loca(glyphs : Array[Bytes]) -> (Bytes, Bytes) {
  let glyf : Array[Byte] = []
  let loca : Array[Byte] = []
  let mut off = 0
  for g in glyphs {
    for b in enc32(off) {
      loca.push(b)
    }
    for b in g {
      glyf.push(b)
    }
    off = off + g.length()
  }
  for b in enc32(off) {
    loca.push(b)
  }
  (Bytes::from_array(glyf), Bytes::from_array(loca))
}

///|
/// 3 頂点の三角形 simple glyph (全 on-curve、座標は i16 形式)。
fn simple_triangle() -> Bytes {
  // ヘッダ 10B: contours=1, bbox (0,0,100,100)
  // endPts 2B: [2]
  // instrLen 2B: 0
  // flags ×3 = 0x01 (on-curve のみ、x/y は i16 delta)
  // x: 0, +100, -50 / y: 0, 0, +100
  let bytes : Array[Byte] = []
  bytes.push(0)
  bytes.push(1) // numberOfContours = 1
  for b in [0, 0, 0, 0, 0, 100, 0, 100] {
    bytes.push(b.to_byte()) // bbox (0,0,100,100)
  }
  bytes.push(0)
  bytes.push(2) // endPtsOfContours = [2]
  bytes.push(0)
  bytes.push(0) // instructionLength = 0
  bytes.push(1)
  bytes.push(1)
  bytes.push(1) // flags
  for v in [0, 100, -50] {
    bytes.push((v >> 8).to_byte())
    bytes.push(v.to_byte())
  }
  for v in [0, 0, 100] {
    bytes.push((v >> 8).to_byte())
    bytes.push(v.to_byte())
  }
  Bytes::from_array(bytes)
}

///|
/// 自分自身を参照する compound glyph (再帰ループ)。
/// header: contours=-1, bbox=(0,0,0,0)
/// component: flags=0x0002 (ARGS_ARE_XY_VALUES), glyphIndex=self, args u8 (0,0)
/// MORE_COMPONENTS なし → 単一 component。
fn self_cycle_compound(self_index : Int32) -> Bytes {
  let bytes : Array[Byte] = []
  bytes.push(0xFF)
  bytes.push(0xFF) // numberOfContours = -1
  for _i = 0; _i < 8; _i = _i + 1 {
    bytes.push(0) // bbox
  }
  bytes.push(0)
  bytes.push(0x02) // flags: ARGS_ARE_XY_VALUES
  bytes.push((self_index >> 8).to_byte())
  bytes.push(self_index.to_byte())
  bytes.push(0)
  bytes.push(0) // args (u8): dx=0, dy=0
  Bytes::from_array(bytes)
}

///|
/// 最小構成の正常フォント: 2 グリフ (0=empty, 1=三角形)。
fn valid_minimal_font() -> Bytes {
  let (glyf, loca) = glyf_loca([Bytes::new(0), simple_triangle()])
  build_font([
    (TAG_HEAD, head_table(1000, 1)),
    (TAG_MAXP, maxp_table(2)),
    (TAG_HHEA, hhea_table(800, -200, 2)),
    (TAG_HMTX, hmtx_table(2)),
    (TAG_LOCA, loca),
    (TAG_GLYF, glyf),
    (TAG_CMAP, cmap_empty_format4()),
  ])
}

///|
/// フォントバイトからの FontFace 構築を試行し、FontError を捕捉して返す。
/// (成功した場合は None = 異常系テストとして失敗扱い)
fn check_face_error(bytes : Bytes) -> FontError? {
  try {
    FontFace::from_data(FontData::from_bytes(bytes), 0) |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
/// グリフアウトライン構築を試行し、FontError を捕捉して返す。
fn check_outline_error(font : Font, glyph_id : Int32) -> FontError? {
  let path = @raden.Path::new()
  try {
    font.append_glyph_outline(glyph_id, 0.0, 0.0, path)
    None
  } catch {
    e => Some(e)
  }
}

///|
test "破損 corpus: 空データは InvalidData" {
  match check_face_error(b"") {
    Some(FontError::InvalidData(_)) => ()
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: sfnt version 不正は InvalidData" {
  let bad = FixedArray::make(64, (0 : Byte))
  bad[0] = 0xDE
  bad[1] = 0xAD
  bad[2] = 0xBE
  bad[3] = 0xEF
  match check_face_error(Bytes::from_array(bad)) {
    Some(FontError::InvalidData(_)) => ()
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: テーブルレコードがデータ長を超過" {
  // ディレクトリに head を登録するが、実データはディレクトリ直後で終了
  let dir_size = 12 + 16
  let bytes = FixedArray::make(dir_size + 8, (0 : Byte))
  bytes[1] = 1 // version 0x00010000
  bytes[5] = 1 // numTables = 1
  // record: tag="head", offset=dir_size, length=100 (実データ不足)
  bytes[12] = (0x68).to_byte()
  bytes[13] = (0x65).to_byte()
  bytes[14] = (0x61).to_byte()
  bytes[15] = (0x64).to_byte()
  bytes[23] = dir_size.to_byte() // offset
  bytes[27] = 100 // length=100 は実長を超過
  match check_face_error(Bytes::from_array(bytes)) {
    Some(FontError::InvalidData(_)) => ()
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: 必須テーブル欠落" {
  // head だけのフォント → maxp 欠落で InvalidData
  let f = build_font([(TAG_HEAD, head_table(1000, 0))])
  match check_face_error(f) {
    Some(FontError::InvalidData(msg)) =>
      assert_true(msg.contains("required table"))
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: units_per_em = 0" {
  let (glyf, loca) = glyf_loca([Bytes::new(0)])
  let f = build_font([
    (TAG_HEAD, head_table(0, 1)),
    (TAG_MAXP, maxp_table(1)),
    (TAG_HHEA, hhea_table(0, 0, 1)),
    (TAG_HMTX, hmtx_table(1)),
    (TAG_LOCA, loca),
    (TAG_GLYF, glyf),
    (TAG_CMAP, cmap_empty_format4()),
  ])
  match check_face_error(f) {
    Some(FontError::InvalidData(msg)) =>
      assert_true(msg.contains("units_per_em"))
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: 正常最小フォントはパースできる" {
  let face = FontFace::from_data(FontData::from_bytes(valid_minimal_font()), 0)
  assert_eq(face.units_per_em(), 1000)
  assert_eq(face.ascent(), 800)
  assert_eq(face.descent(), -200)
  // cmap は全文字 → 0
  let font = Font::from_face(face, 16.0)
  assert_eq(font.map_char_to_glyph('A'), 0)
  assert_eq(font.glyph_advance(1), 8.0) // 500 * 16/1000
}

///|
test "破損 corpus: simple glyph の三角形が Path になる" {
  let face = FontFace::from_data(FontData::from_bytes(valid_minimal_font()), 0)
  let font = Font::from_face(face, 16.0)
  let path = @raden.Path::new()
  font.append_glyph_outline(1, 0.0, 0.0, path)
  assert_false(path.is_empty())
  match path.bounding_box() {
    Some(bb) => {
      // 三角形 (0,0)-(100,0)-(50,100) × 16/1000、Y 反転
      assert_true(bb.w > 0.0)
      assert_true(bb.h > 0.0)
    }
    None => fail("path bbox が必要")
  }
}

///|
test "破損 corpus: compound glyph の自己参照サイクルは InvalidData" {
  let (glyf, loca) = glyf_loca([Bytes::new(0), self_cycle_compound(1)])
  let f = build_font([
    (TAG_HEAD, head_table(1000, 1)),
    (TAG_MAXP, maxp_table(2)),
    (TAG_HHEA, hhea_table(800, -200, 2)),
    (TAG_HMTX, hmtx_table(2)),
    (TAG_LOCA, loca),
    (TAG_GLYF, glyf),
    (TAG_CMAP, cmap_empty_format4()),
  ])
  let face = FontFace::from_data(FontData::from_bytes(f), 0)
  let font = Font::from_face(face, 16.0)
  // 深度制限 (MAX_COMPOUND_DEPTH) で InvalidData を返す。無限ループしない。
  match check_outline_error(font, 1) {
    Some(FontError::InvalidData(msg)) => assert_true(msg.contains("recursion"))
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: glyf 範囲外のグリフは InvalidData" {
  // loca が glyf 実データを超過するフォント
  let (glyf, loca) = glyf_loca([simple_triangle()])
  // loca[1] を巨大値に書き換え
  let loca_arr = FixedArray::makei(loca.length(), fn(i) { loca[i] })
  loca_arr[4] = 0xFF
  loca_arr[5] = 0xFF
  let f = build_font([
    (TAG_HEAD, head_table(1000, 1)),
    (TAG_MAXP, maxp_table(1)),
    (TAG_HHEA, hhea_table(800, -200, 1)),
    (TAG_HMTX, hmtx_table(1)),
    (TAG_LOCA, Bytes::from_array(loca_arr)),
    (TAG_GLYF, glyf),
    (TAG_CMAP, cmap_empty_format4()),
  ])
  let face = FontFace::from_data(FontData::from_bytes(f), 0)
  let font = Font::from_face(face, 16.0)
  match check_outline_error(font, 0) {
    Some(FontError::InvalidData(_)) => ()
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: glyph_id 範囲外は InvalidData" {
  let face = FontFace::from_data(FontData::from_bytes(valid_minimal_font()), 0)
  let font = Font::from_face(face, 16.0)
  match check_outline_error(font, 99) {
    Some(FontError::InvalidData(_)) => ()
    _ => fail("InvalidData を期待")
  }
}

///|
test "破損 corpus: 断片化された glyf (ヘッダ 10B 未満)" {
  // loca[0]=0, loca[1]=4 → 4 バイトのグリフ (ヘッダ 10B に足りない)
  let glyf = Bytes::from_array([1, 2, 3, 4])
  let loca = Bytes::from_array([0, 0, 0, 0, 0, 0, 0, 4])
  let f = build_font([
    (TAG_HEAD, head_table(1000, 1)),
    (TAG_MAXP, maxp_table(1)),
    (TAG_HHEA, hhea_table(800, -200, 1)),
    (TAG_HMTX, hmtx_table(1)),
    (TAG_LOCA, loca),
    (TAG_GLYF, glyf),
    (TAG_CMAP, cmap_empty_format4()),
  ])
  let face = FontFace::from_data(FontData::from_bytes(f), 0)
  let font = Font::from_face(face, 16.0)
  match check_outline_error(font, 0) {
    Some(FontError::InvalidData(_)) => ()
    _ => fail("InvalidData を期待")
  }
}
