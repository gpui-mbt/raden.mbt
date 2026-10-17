/// TrueType テーブルパーサ。
///
/// sfnt ヘッダからテーブルディレクトリをパースし、
/// head, maxp, hhea, hmtx, loca, cmap, glyf, OS/2 の各テーブルを読み出す。
/// OS/2 テーブルは cap_height / x_height の取得にのみ利用する。
/// GSUB / GPOS はパース失敗をエラーへせず空テーブルに縮退する (上流の寛容方針)。

// ---------------------------------------------------------------------------
// バイト読み取りヘルパー (厳格: 範囲外は FontError)
// ---------------------------------------------------------------------------

///|
fn be_u16(data : BytesView, offset : Int32) -> Int32 raise FontError {
  if offset < 0 || offset + 2 > data.length() {
    raise FontError::InvalidData("unexpected end of data (u16)")
  }
  (data[offset].to_int() << 8) | data[offset + 1].to_int()
}

///|
fn be_i16(data : BytesView, offset : Int32) -> Int32 raise FontError {
  let v = be_u16(data, offset)
  // i16 への縮小: 符号拡張を手動で行う
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
fn be_u32(data : BytesView, offset : Int32) -> Int32 raise FontError {
  if offset < 0 || offset + 4 > data.length() {
    raise FontError::InvalidData("unexpected end of data (u32)")
  }
  (data[offset].to_int() << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}

///|
fn be_u8(data : BytesView, offset : Int32) -> Int32 raise FontError {
  if offset < 0 || offset >= data.length() {
    raise FontError::InvalidData("unexpected end of data (u8)")
  }
  data[offset].to_int()
}

///|
fn be_i8(data : BytesView, offset : Int32) -> Int32 raise FontError {
  let v = be_u8(data, offset)
  if v >= 0x80 {
    v - 0x100
  } else {
    v
  }
}

// ---------------------------------------------------------------------------
// 寛容ヘルパー (GSUB/GPOS 用: 失敗は None)
// ---------------------------------------------------------------------------

///|
fn opt_u16(data : BytesView, offset : Int32) -> Int32? {
  Some(be_u16(data, offset)) catch {
    _ => None
  }
}

///|
fn opt_i16(data : BytesView, offset : Int32) -> Int32? {
  Some(be_i16(data, offset)) catch {
    _ => None
  }
}

///|
fn opt_u32(data : BytesView, offset : Int32) -> Int32? {
  Some(be_u32(data, offset)) catch {
    _ => None
  }
}

// ---------------------------------------------------------------------------
// テーブルディレクトリ
// ---------------------------------------------------------------------------

///|
/// テーブルの位置情報。
priv struct TableRecord {
  offset : Int32
  length : Int32
}

///|
/// テーブルディレクトリ。tag → (offset, length) のマッピング。
priv struct TableDirectory {
  records : Array[(Int32, TableRecord)]
}

///|
fn TableDirectory::parse(
  data : BytesView,
  start : Int32,
) -> TableDirectory raise FontError {
  if data.length() < start + 12 {
    raise FontError::InvalidData("data too short for sfnt header")
  }
  let sfnt_version = be_u32(data, start)
  // TrueType: 0x00010000、'true' (0x74727565) も許容 (Apple)
  if sfnt_version != 0x00010000 && sfnt_version != 0x74727565 {
    raise FontError::InvalidData("unsupported sfnt version")
  }
  let num_tables = be_u16(data, start + 4)
  let header_end = start + 12 + num_tables * 16
  if data.length() < header_end {
    raise FontError::InvalidData("data too short for table directory")
  }
  let records : Array[(Int32, TableRecord)] = []
  for i = 0; i < num_tables; i = i + 1 {
    let base = start + 12 + i * 16
    let tag = be_u32(data, base)
    let offset = be_u32(data, base + 8)
    let length = be_u32(data, base + 12)
    // テーブル範囲が実データに収まるか検証。
    // Int は 32 bit のため u32 最大値が負に折り返される場合があるが、
    // data.length() < 2^31 が常に成立するため負値 = 上流 usize 判定で
    // 拒否される巨大値と同値であり、ここで明示的に弾く。
    if offset < 0 || length < 0 || offset + length > data.length() {
      raise FontError::InvalidData("table record exceeds data length")
    }
    records.push((tag, { offset, length, }))
  }
  { records, }
}

///|
fn TableDirectory::find(self : TableDirectory, tag : Int32) -> TableRecord? {
  for r in self.records {
    if r.0 == tag {
      return Some(r.1)
    }
  }
  None
}

///|
fn TableDirectory::require(
  self : TableDirectory,
  tag : Int32,
) -> TableRecord raise FontError {
  match self.find(tag) {
    Some(r) => r
    None => raise FontError::InvalidData("required table not found")
  }
}

///|
const TAG_HEAD : Int32 = 0x68656164 // "head"

///|
const TAG_MAXP : Int32 = 0x6D617870 // "maxp"

///|
const TAG_HHEA : Int32 = 0x68686561 // "hhea"

///|
const TAG_HMTX : Int32 = 0x686D7478 // "hmtx"

///|
const TAG_LOCA : Int32 = 0x6C6F6361 // "loca"

///|
const TAG_CMAP : Int32 = 0x636D6170 // "cmap"

///|
const TAG_GLYF : Int32 = 0x676C7966 // "glyf"

///|
const TAG_OS2 : Int32 = 0x4F532F32 // "OS/2"

///|
const TAG_GSUB : Int32 = 0x47535542 // "GSUB"

///|
const TAG_GPOS : Int32 = 0x47504F53 // "GPOS"

///|
const TAG_TTCF : Int32 = 0x74746366 // "ttcf"

///|
/// OpenType Layout feature tag 定数。
const TAG_LIGA : Int32 = 0x6C696761 // "liga"

///|
const TAG_CLIG : Int32 = 0x636C6967 // "clig"

///|
const TAG_KERN : Int32 = 0x6B65726E // "kern"

///|
/// OpenType Layout script tag 定数。
const TAG_DFLT : Int32 = 0x44464C54 // "DFLT"

///|
const TAG_LATN : Int32 = 0x6C61746E // "latn"

// ---------------------------------------------------------------------------
// head テーブル
// ---------------------------------------------------------------------------

///|
priv struct HeadTable {
  units_per_em : Int32
  index_to_loc_format : Int32
}

///|
fn parse_head(data : BytesView, rec : TableRecord) -> HeadTable raise FontError {
  let off = rec.offset
  if rec.length < 54 {
    raise FontError::InvalidData("head table too short")
  }
  let units_per_em = be_u16(data, off + 18)
  if units_per_em == 0 {
    raise FontError::InvalidData("units_per_em is zero")
  }
  let index_to_loc_format = be_i16(data, off + 50)
  { units_per_em, index_to_loc_format, }
}

// ---------------------------------------------------------------------------
// maxp テーブル
// ---------------------------------------------------------------------------

///|
fn parse_maxp(data : BytesView, rec : TableRecord) -> Int32 raise FontError {
  let off = rec.offset
  if rec.length < 6 {
    raise FontError::InvalidData("maxp table too short")
  }
  be_u16(data, off + 4)
}

// ---------------------------------------------------------------------------
// hhea テーブル
// ---------------------------------------------------------------------------

///|
priv struct HheaTable {
  ascent : Int32
  descent : Int32
  line_gap : Int32
  number_of_h_metrics : Int32
}

///|
fn parse_hhea(data : BytesView, rec : TableRecord) -> HheaTable raise FontError {
  let off = rec.offset
  if rec.length < 36 {
    raise FontError::InvalidData("hhea table too short")
  }
  {
    ascent: be_i16(data, off + 4),
    descent: be_i16(data, off + 6),
    line_gap: be_i16(data, off + 8),
    number_of_h_metrics: be_u16(data, off + 34),
  }
}

// ---------------------------------------------------------------------------
// OS/2 テーブル
// ---------------------------------------------------------------------------

///|
/// OS/2 テーブルから取得する cap / x 高さ。
/// OS/2 v2 以上の sCapHeight / sxHeight フィールドに対応する。
priv struct Os2Table {
  cap_height : Int32?
  x_height : Int32?
}

///|
fn parse_os2(data : BytesView, rec : TableRecord) -> Os2Table raise FontError {
  let off = rec.offset
  // Microsoft 拡張形式の OS/2 version 0 最小サイズは 78 バイト。
  // Apple 旧形式 68 バイトは現代の OS バンドルフォントに存在しないためエラーとする。
  if rec.length < 78 {
    raise FontError::InvalidData("OS/2 table too short")
  }
  let version = be_u16(data, off)
  if version < 2 {
    // v0 / v1 では sCapHeight / sxHeight が存在しない。
    return { cap_height: None, x_height: None, }
  }
  // OpenType 仕様 OS/2 v2+ の sxHeight (offset 86) + sCapHeight (offset 88)
  // を読むには 90 バイト必要。不足時は寛容方針で None を返す。
  if rec.length < 90 {
    return { cap_height: None, x_height: None, }
  }
  {
    cap_height: Some(be_i16(data, off + 88)),
    x_height: Some(be_i16(data, off + 86)),
  }
}

// ---------------------------------------------------------------------------
// hmtx テーブル
// ---------------------------------------------------------------------------

///|
priv struct HmtxTable {
  /// advance_width[i] (i < number_of_h_metrics のときは各グリフ固有、
  /// i >= number_of_h_metrics のときは最後の値を使う)。
  advance_widths : Array[Int32]
  lsbs : Array[Int32]
}

///|
fn parse_hmtx(
  data : BytesView,
  rec : TableRecord,
  num_h_metrics : Int32,
  num_glyphs : Int32,
) -> HmtxTable raise FontError {
  let off = rec.offset
  let nh = num_h_metrics
  let ng = num_glyphs
  // longHorMetric[nh] + leftSideBearing[ng - nh]
  let min_len = nh * 4 + (if ng > nh { ng - nh } else { 0 }) * 2
  if rec.length < min_len {
    raise FontError::InvalidData("hmtx table too short")
  }
  let advance_widths : Array[Int32] = []
  let lsbs : Array[Int32] = []
  for i = 0; i < nh; i = i + 1 {
    let base = off + i * 4
    advance_widths.push(be_u16(data, base))
    lsbs.push(be_i16(data, base + 2))
  }
  // 残りのグリフは最後の advance_width を継承
  let last_aw = if advance_widths.is_empty() {
    0
  } else {
    advance_widths[advance_widths.length() - 1]
  }
  let extra_base = off + nh * 4
  for i = 0; i < ng - nh; i = i + 1 {
    advance_widths.push(last_aw)
    lsbs.push(be_i16(data, extra_base + i * 2))
  }
  { advance_widths, lsbs, }
}

// ---------------------------------------------------------------------------
// loca テーブル
// ---------------------------------------------------------------------------

///|
fn parse_loca(
  data : BytesView,
  rec : TableRecord,
  num_glyphs : Int32,
  index_to_loc_format : Int32,
) -> Array[Int32] raise FontError {
  let off = rec.offset
  let n = num_glyphs + 1 // loca は num_glyphs + 1 エントリ
  let offsets : Array[Int32] = []
  if index_to_loc_format == 0 {
    // short format: u16 * 2
    if rec.length < n * 2 {
      raise FontError::InvalidData("loca table too short (short)")
    }
    for i = 0; i < n; i = i + 1 {
      offsets.push(be_u16(data, off + i * 2) * 2)
    }
  } else {
    // long format: u32
    if rec.length < n * 4 {
      raise FontError::InvalidData("loca table too short (long)")
    }
    for i = 0; i < n; i = i + 1 {
      offsets.push(be_u32(data, off + i * 4))
    }
  }
  offsets
}

// ---------------------------------------------------------------------------
// cmap テーブル
// ---------------------------------------------------------------------------

///|
/// Unicode → GlyphID ルックアップ。
priv enum CmapLookup {
  Format4(CmapFormat4)
  Format12(CmapFormat12)
}

///|
priv struct CmapFormat4 {
  segments : Array[CmapFormat4Segment]
  /// glyphIdArray 全体 (id_range_offset で参照する)。
  glyph_id_array : Array[Int32]
  /// glyphIdArray のバイトオフセット (id_range_offset の基点計算用)。
  glyph_id_array_offset : Int32
  /// idRangeOffset 配列のバイトオフセット。
  id_range_offset_base : Int32
}

///|
priv struct CmapFormat4Segment {
  end_code : Int32
  start_code : Int32
  id_delta : Int32
  id_range_offset : Int32
}

///|
priv struct CmapFormat12 {
  groups : Array[CmapFormat12Group]
}

///|
priv struct CmapFormat12Group {
  start_char : Int32
  end_char : Int32
  start_glyph_id : Int32
}

///|
fn CmapLookup::map(self : CmapLookup, codepoint : Int32) -> Int32 {
  match self {
    CmapLookup::Format4(f4) => f4.map(codepoint)
    CmapLookup::Format12(f12) => f12.map(codepoint)
  }
}

///|
fn CmapFormat4::map(self : CmapFormat4, codepoint : Int32) -> Int32 {
  if codepoint > 0xFFFF {
    return 0
  }
  let cp = codepoint
  // 二分探索で該当セグメントを見つける (end_code >= cp の最小 index)
  let segs = self.segments
  let mut lo = 0
  let mut hi = segs.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if segs[mid].end_code < cp {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo >= segs.length() {
    return 0
  }
  let seg = segs[lo]
  if cp < seg.start_code {
    return 0
  }
  if seg.id_range_offset == 0 {
    // id_delta 方式 (modulo 65536 wrap)
    (cp + seg.id_delta) & 0xFFFF
  } else {
    // id_range_offset 方式:
    // glyphId = glyphIdArray[idRangeOffset[i]/2 + (cp - startCode) + i]
    // (idRangeOffset[i] の位置からの相対オフセット)
    let seg_byte_offset = self.id_range_offset_base + lo * 2
    let target_byte_offset = seg_byte_offset +
      seg.id_range_offset +
      (cp - seg.start_code) * 2
    let array_index = (target_byte_offset - self.glyph_id_array_offset) / 2
    if array_index < 0 || array_index >= self.glyph_id_array.length() {
      return 0
    }
    let glyph_id = self.glyph_id_array[array_index]
    if glyph_id == 0 {
      0
    } else {
      (glyph_id + seg.id_delta) & 0xFFFF
    }
  }
}

///|
fn CmapFormat12::map(self : CmapFormat12, codepoint : Int32) -> Int32 {
  // 二分探索: start_char <= codepoint の最大 index
  let groups = self.groups
  let mut lo = 0
  let mut hi = groups.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if groups[mid].start_char <= codepoint {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo == 0 {
    return 0
  }
  let g = groups[lo - 1]
  if codepoint > g.end_char {
    return 0
  }
  let glyph_id = g.start_glyph_id + (codepoint - g.start_char)
  if glyph_id > 0xFFFF {
    return 0
  }
  glyph_id
}

///|
fn parse_cmap(
  data : BytesView,
  rec : TableRecord,
) -> CmapLookup raise FontError {
  let off = rec.offset
  if rec.length < 4 {
    raise FontError::InvalidData("cmap table too short")
  }
  let num_tables = be_u16(data, off + 2)
  if rec.length < 4 + num_tables * 8 {
    raise FontError::InvalidData("cmap table too short for encoding records")
  }
  // 最適なサブテーブルを選択する
  // 優先: platformID=3 encodingID=10 (UCS-4) > platformID=3 encodingID=1 (UCS-2)
  //       platformID=0 encodingID=3..6 も許容
  let mut best_offset : Int32? = None
  let mut best_priority = 0
  for i = 0; i < num_tables; i = i + 1 {
    let base = off + 4 + i * 8
    let platform_id = be_u16(data, base)
    let encoding_id = be_u16(data, base + 2)
    let subtable_offset = be_u32(data, base + 4)
    let priority = match (platform_id, encoding_id) {
      (3, 10) => 4 // Windows UCS-4
      (0, e) if e >= 4 && e <= 6 => 3 // Unicode full
      (3, 1) => 2 // Windows UCS-2
      (0, 3) => 1 // Unicode BMP
      _ => 0
    }
    if priority > best_priority {
      best_priority = priority
      best_offset = Some(subtable_offset)
    }
  }
  let subtable_rel = match best_offset {
    Some(v) => v
    None => raise FontError::InvalidData("no suitable cmap subtable")
  }
  let subtable_off = off + subtable_rel
  if subtable_off + 2 > data.length() {
    raise FontError::InvalidData("cmap subtable offset out of range")
  }
  let format = be_u16(data, subtable_off)
  match format {
    4 => parse_cmap_format4(data, subtable_off)
    12 => parse_cmap_format12(data, subtable_off)
    _ => raise FontError::InvalidData("unsupported cmap format")
  }
}

///|
fn parse_cmap_format4(
  data : BytesView,
  off : Int32,
) -> CmapLookup raise FontError {
  if off + 14 > data.length() {
    raise FontError::InvalidData("cmap format 4 header too short")
  }
  let length = be_u16(data, off + 2)
  if off + length > data.length() {
    raise FontError::InvalidData("cmap format 4 length exceeds data")
  }
  let seg_count = be_u16(data, off + 6) / 2
  // 各配列のオフセット
  let end_codes_off = off + 14
  // reservedPad: 2 bytes after end_codes
  let start_codes_off = end_codes_off + seg_count * 2 + 2
  let id_deltas_off = start_codes_off + seg_count * 2
  let id_range_offsets_off = id_deltas_off + seg_count * 2
  let glyph_id_array_off = id_range_offsets_off + seg_count * 2
  let table_end = off + length
  if glyph_id_array_off > table_end {
    raise FontError::InvalidData("cmap format 4 arrays exceed table length")
  }
  let segments : Array[CmapFormat4Segment] = []
  for i = 0; i < seg_count; i = i + 1 {
    segments.push({
      end_code: be_u16(data, end_codes_off + i * 2),
      start_code: be_u16(data, start_codes_off + i * 2),
      id_delta: be_i16(data, id_deltas_off + i * 2),
      id_range_offset: be_u16(data, id_range_offsets_off + i * 2),
    })
  }
  // glyphIdArray
  let glyph_id_array : Array[Int32] = []
  for i = 0; i * 2 + 1 < table_end - glyph_id_array_off; i = i + 1 {
    glyph_id_array.push(be_u16(data, glyph_id_array_off + i * 2))
  }
  CmapLookup::Format4({
    segments,
    glyph_id_array,
    glyph_id_array_offset: glyph_id_array_off,
    id_range_offset_base: id_range_offsets_off,
  })
}

///|
fn parse_cmap_format12(
  data : BytesView,
  off : Int32,
) -> CmapLookup raise FontError {
  // format 12 は fixed32 format (先頭 u16=12, 次の u16=0, 次 u32=length)
  if off + 16 > data.length() {
    raise FontError::InvalidData("cmap format 12 header too short")
  }
  let num_groups = be_u32(data, off + 12)
  let groups_off = off + 16
  if groups_off + num_groups * 12 > data.length() {
    raise FontError::InvalidData("cmap format 12 groups exceed data")
  }
  let groups : Array[CmapFormat12Group] = []
  for i = 0; i < num_groups; i = i + 1 {
    let base = groups_off + i * 12
    groups.push({
      start_char: be_u32(data, base),
      end_char: be_u32(data, base + 4),
      start_glyph_id: be_u32(data, base + 8),
    })
  }
  CmapLookup::Format12({ groups, })
}

// ---------------------------------------------------------------------------
// GSUB / GPOS テーブル
// ---------------------------------------------------------------------------

///|
priv struct GsubTable {
  /// DefaultLangSys 内の FeatureIndex 順に並べた、有効な置換 feature の Lookup 参照。
  /// タプルは (feature tag, lookup index)。`liga` / `clig` のみを含む。
  applicable_lookups : Array[(Int32, Int32)]
  lookups : Array[GsubLookup]
}

///|
fn GsubTable::empty() -> GsubTable {
  { applicable_lookups: [], lookups: [], }
}

///|
priv enum GsubLookup {
  Single(Array[GsubSingleSubst])
  Ligature(Array[GsubLigatureSubst])
  Unsupported
}

///|
priv struct GsubSingleSubst {
  coverage : Coverage
  format : GsubSingleSubstFormat
}

///|
priv enum GsubSingleSubstFormat {
  /// Format 1: delta_glyph_id 加算 (modulo 65536 wrap)
  DeltaGlyphID(Int32)
  /// Format 2: substitute glyph IDs 配列
  SubstituteGlyphIDs(Array[Int32])
}

///|
priv struct GsubLigatureSubst {
  coverage : Coverage
  /// LigatureSet[Coverage Index] のリスト。各エントリは Ligature の配列。
  ligature_sets : Array[Array[GsubLigature]]
}

///|
priv struct GsubLigature {
  ligature_glyph : Int32
  /// 合字を構成する 2 番目以降のグリフ ID のみを保持する (N-1 要素)。
  component_glyph_ids : Array[Int32]
}

///|
priv struct GposTable {
  /// `kern` feature が参照する Lookup インデックスのリスト (重複除去済み)。
  kern_lookups : Array[Int32]
  lookups : Array[GposLookup]
}

///|
fn GposTable::empty() -> GposTable {
  { kern_lookups: [], lookups: [], }
}

///|
priv enum GposLookup {
  Single(Array[GposSingleAdjust])
  Pair(Array[GposPairAdjust])
  Unsupported
}

///|
priv struct GposSingleAdjust {
  coverage : Coverage
  format : GposSingleAdjustFormat
}

///|
priv enum GposSingleAdjustFormat {
  /// Format 1: 全 Coverage に同じ ValueRecord
  Uniform(ValueRecord)
  /// Format 2: Coverage Index 別の ValueRecord
  PerGlyph(Array[ValueRecord])
}

///|
priv struct GposPairAdjust {
  coverage : Coverage
  format : GposPairAdjustFormat
}

///|
priv enum GposPairAdjustFormat {
  /// Format 1: PairSet[Coverage Index] のリスト
  PairSet(Array[Array[GposPair]])
  /// Format 2: Class1 x Class2 マトリクス
  Class(ClassDef, ClassDef, Int32, Int32, Array[(ValueRecord, ValueRecord)])
}

///|
priv struct GposPair {
  second_glyph : Int32
  value1 : ValueRecord
  value2 : ValueRecord
}

///|
priv struct ValueRecord {
  mut x_placement : Int32
  mut y_placement : Int32
  mut x_advance : Int32
  mut y_advance : Int32
}

///|
fn ValueRecord::default() -> ValueRecord {
  { x_placement: 0, y_placement: 0, x_advance: 0, y_advance: 0, }
}

///|
priv enum Coverage {
  /// Format 1: glyph 列挙 (昇順前提、binary_search で検索)
  GlyphList(Array[Int32])
  /// Format 2: (start, end, start_coverage_index) のタプル列
  RangeList(Array[(Int32, Int32, Int32)])
}

///|
priv enum ClassDef {
  Format1(Int32, Array[Int32])
  /// (start, end, class) の範囲列。範囲外グリフは class = 0 として扱う
  Format2(Array[(Int32, Int32, Int32)])
}

///|
fn GsubTable::lookup_at(self : GsubTable, index : Int32) -> GsubLookup? {
  if index < 0 || index >= self.lookups.length() {
    return None
  }
  Some(self.lookups[index])
}

///|
fn GposTable::lookup_at(self : GposTable, index : Int32) -> GposLookup? {
  if index < 0 || index >= self.lookups.length() {
    return None
  }
  Some(self.lookups[index])
}

///|
fn GposPairAdjust::lookup(
  self : GposPairAdjust,
  g1 : Int32,
  g2 : Int32,
) -> (ValueRecord, ValueRecord)? {
  guard self.coverage.index_of(g1) is Some(coverage_index) else { return None }
  match self.format {
    PairSet(sets) => {
      guard coverage_index < sets.length() else { return None }
      for p in sets[coverage_index] {
        if p.second_glyph == g2 {
          return Some((p.value1, p.value2))
        }
      }
      None
    }
    Class(class_def_1, class_def_2, class1_count, class2_count, records) => {
      let class1 = class_def_1.class_of(g1)
      let class2 = class_def_2.class_of(g2)
      if class1 >= class1_count || class2 >= class2_count {
        return None
      }
      let idx = class1 * class2_count + class2
      if idx < 0 || idx >= records.length() {
        return None
      }
      Some(records[idx])
    }
  }
}

///|
/// Coverage に含まれるグリフ数を返す。
fn Coverage::glyph_count(self : Coverage) -> Int32 {
  match self {
    GlyphList(list) => list.length()
    RangeList(ranges) => {
      let mut total = 0
      for r in ranges {
        let (start, end, _) = r
        if start <= end {
          total = total + (end - start + 1)
        }
      }
      total
    }
  }
}

///|
/// Coverage Format 1 で glyph_ids が昇順でない不正フォントの場合、
/// 二分探索は失敗し `None` に縮退する。結果としてシェーピングは
/// 当該グリフで noop となる (上流と同じ挙動)。
fn Coverage::index_of(self : Coverage, glyph_id : Int32) -> Int32? {
  match self {
    GlyphList(list) => {
      // binary_search (昇順前提)
      let mut lo = 0
      let mut hi = list.length()
      while lo < hi {
        let mid = (lo + hi) / 2
        if list[mid] < glyph_id {
          lo = mid + 1
        } else if list[mid] > glyph_id {
          hi = mid
        } else {
          return Some(mid)
        }
      }
      None
    }
    RangeList(ranges) => {
      for r in ranges {
        let (start, end, start_idx) = r
        if glyph_id >= start && glyph_id <= end {
          let idx = start_idx + (glyph_id - start)
          return if idx <= 0xFFFF { Some(idx) } else { None }
        }
      }
      None
    }
  }
}

///|
fn ClassDef::class_of(self : ClassDef, glyph_id : Int32) -> Int32 {
  match self {
    Format1(start_glyph, class_values) => {
      if glyph_id < start_glyph {
        return 0
      }
      let idx = glyph_id - start_glyph
      if idx >= class_values.length() {
        return 0
      }
      class_values[idx]
    }
    Format2(ranges) => {
      for r in ranges {
        let (start, end, class) = r
        if glyph_id >= start && glyph_id <= end {
          return class
        }
      }
      0
    }
  }
}

///|
/// GSUB / GPOS テーブル共通のヘッダ解析結果。
priv struct LayoutTableInfo {
  table_end : Int32
  feature_list_off : Int32
  feature_indices : Array[Int32]
  lookup_list_off : Int32
}

///|
/// GSUB / GPOS テーブルの共通ヘッダを解析し、DefaultLangSys 経由で有効となる
/// FeatureIndex 列と各リストへのオフセットを返す。
fn parse_layout_table_header(
  data : BytesView,
  rec : TableRecord,
) -> LayoutTableInfo? {
  let off = rec.offset
  let table_end = off + rec.length
  if table_end > data.length() || rec.length < 10 {
    return None
  }
  guard opt_u32(data, off) is Some(version) else { return None }
  if version != 0x00010000 && version != 0x00010001 {
    return None
  }
  guard opt_u16(data, off + 4) is Some(script_list_rel) else { return None }
  guard opt_u16(data, off + 6) is Some(feature_list_rel) else { return None }
  guard opt_u16(data, off + 8) is Some(lookup_list_rel) else { return None }
  let script_list_off = off + script_list_rel
  let feature_list_off = off + feature_list_rel
  let lookup_list_off = off + lookup_list_rel
  if script_list_off > table_end ||
    feature_list_off + 2 > table_end ||
    lookup_list_off > table_end {
    return None
  }
  guard find_script(data, script_list_off, table_end) is Some(script_off) else {
    return None
  }
  guard opt_u16(data, script_off) is Some(default_lang_sys_rel) else {
    return None
  }
  if default_lang_sys_rel == 0 {
    return None
  }
  let lang_sys_off = script_off + default_lang_sys_rel
  if lang_sys_off + 4 > table_end {
    return None
  }
  guard opt_u16(data, lang_sys_off + 4) is Some(feature_count) else {
    return None
  }
  let feature_indices : Array[Int32] = []
  for i = 0; i < feature_count; i = i + 1 {
    guard opt_u16(data, lang_sys_off + 6 + i * 2) is Some(idx) else {
      return None
    }
    feature_indices.push(idx)
  }
  Some({ table_end, feature_list_off, feature_indices, lookup_list_off, })
}

///|
/// FeatureList を走査し、有効な feature ごとに (tag, lookup_indices) を返す。
/// FeatureIndex が FeatureCount を超える場合は無視する。
fn read_feature_lookups(
  data : BytesView,
  feature_list_off : Int32,
  table_end : Int32,
  total_features : Int32,
  feature_indices : Array[Int32],
) -> Array[(Int32, Array[Int32])] {
  let out : Array[(Int32, Array[Int32])] = []
  for fi in feature_indices {
    if fi >= total_features {
      continue
    }
    let feature_record_off = feature_list_off + 2 + fi * 6
    if feature_record_off + 6 > table_end {
      continue
    }
    guard opt_u32(data, feature_record_off) is Some(tag) else { continue }
    guard opt_u16(data, feature_record_off + 4) is Some(feature_table_rel) else {
      continue
    }
    let feature_table_off = feature_list_off + feature_table_rel
    if feature_table_off + 4 > table_end {
      continue
    }
    guard opt_u16(data, feature_table_off + 2) is Some(lookup_index_count) else {
      continue
    }
    let records_end = feature_table_off + 4 + lookup_index_count * 2
    if records_end > table_end {
      continue
    }
    let lookup_indices : Array[Int32] = []
    for i = 0; i < lookup_index_count; i = i + 1 {
      guard opt_u16(data, feature_table_off + 4 + i * 2) is Some(idx) else {
        continue
      }
      lookup_indices.push(idx)
    }
    out.push((tag, lookup_indices))
  }
  out
}

///|
/// GSUB テーブルをパースする (寛容方針: 失敗は空テーブル)。
fn parse_gsub(data : BytesView, rec : TableRecord) -> GsubTable {
  let out : Array[(Int32, Int32)] = []
  let lookups : Array[GsubLookup] = []
  guard parse_layout_table_header(data, rec) is Some(info) else {
    return { applicable_lookups: [], lookups: [], }
  }
  guard opt_u16(data, info.feature_list_off) is Some(total_features) else {
    return { applicable_lookups: [], lookups: [], }
  }
  let feature_lookups = read_feature_lookups(
    data,
    info.feature_list_off,
    info.table_end,
    total_features,
    info.feature_indices,
  )
  // (tag, idx) の重複除去 (上流の HashSet と同じ効果、小配列なので線形で足りる)
  for fl in feature_lookups {
    let (tag, lookup_indices) = fl
    if tag == TAG_LIGA || tag == TAG_CLIG {
      for idx in lookup_indices {
        let mut seen = false
        for a in out {
          if a.0 == tag && a.1 == idx {
            seen = true
            break
          }
        }
        if !seen {
          out.push((tag, idx))
        }
      }
    }
  }
  if info.lookup_list_off + 2 <= info.table_end {
    guard opt_u16(data, info.lookup_list_off) is Some(lookup_count) else {
      return { applicable_lookups: out, lookups, }
    }
    for i = 0; i < lookup_count; i = i + 1 {
      let rel_off = info.lookup_list_off + 2 + i * 2
      if rel_off + 2 > info.table_end {
        continue
      }
      guard opt_u16(data, rel_off) is Some(rel) else { continue }
      let lookup_off = info.lookup_list_off + rel
      lookups.push(parse_gsub_lookup(data, lookup_off, info.table_end))
    }
  }
  { applicable_lookups: out, lookups, }
}

///|
/// GPOS テーブルをパースする (寛容方針: 失敗は空テーブル)。
fn parse_gpos(data : BytesView, rec : TableRecord) -> GposTable {
  let kern_lookups : Array[Int32] = []
  let lookups : Array[GposLookup] = []
  guard parse_layout_table_header(data, rec) is Some(info) else {
    return { kern_lookups: [], lookups: [], }
  }
  guard opt_u16(data, info.feature_list_off) is Some(total_features) else {
    return { kern_lookups: [], lookups: [], }
  }
  let feature_lookups = read_feature_lookups(
    data,
    info.feature_list_off,
    info.table_end,
    total_features,
    info.feature_indices,
  )
  for fl in feature_lookups {
    let (tag, lookup_indices) = fl
    if tag == TAG_KERN {
      for idx in lookup_indices {
        if !kern_lookups.contains(idx) {
          kern_lookups.push(idx)
        }
      }
    }
  }
  if info.lookup_list_off + 2 <= info.table_end {
    guard opt_u16(data, info.lookup_list_off) is Some(lookup_count) else {
      return { kern_lookups, lookups, }
    }
    for i = 0; i < lookup_count; i = i + 1 {
      let rel_off = info.lookup_list_off + 2 + i * 2
      if rel_off + 2 > info.table_end {
        continue
      }
      guard opt_u16(data, rel_off) is Some(rel) else { continue }
      let lookup_off = info.lookup_list_off + rel
      lookups.push(parse_gpos_lookup(data, lookup_off, info.table_end))
    }
  }
  { kern_lookups, lookups, }
}

///|
/// 'DFLT' を優先、なければ 'latn' を採用する。
fn find_script(
  data : BytesView,
  script_list_off : Int32,
  table_end : Int32,
) -> Int32? {
  if script_list_off + 2 > table_end {
    return None
  }
  guard opt_u16(data, script_list_off) is Some(script_count) else {
    return None
  }
  let mut dflt_off : Int32? = None
  let mut latn_off : Int32? = None
  for i = 0; i < script_count; i = i + 1 {
    let record_off = script_list_off + 2 + i * 6
    if record_off + 6 > table_end {
      continue
    }
    guard opt_u32(data, record_off) is Some(tag) else { continue }
    guard opt_u16(data, record_off + 4) is Some(rel) else { continue }
    let script_off = script_list_off + rel
    if script_off + 2 > table_end {
      continue
    }
    if tag == TAG_DFLT {
      dflt_off = Some(script_off)
    } else if tag == TAG_LATN {
      latn_off = Some(script_off)
    }
  }
  match dflt_off {
    Some(v) => Some(v)
    None => latn_off
  }
}

///|
/// GSUB Lookup をパースする (Type 1 Single / Type 4 Ligature / Type 7 Extension)。
fn parse_gsub_lookup(
  data : BytesView,
  lookup_off : Int32,
  table_end : Int32,
) -> GsubLookup {
  if lookup_off + 8 > table_end {
    return GsubLookup::Unsupported
  }
  guard opt_u16(data, lookup_off) is Some(lookup_type) else {
    return GsubLookup::Unsupported
  }
  guard opt_u16(data, lookup_off + 4) is Some(subtable_count) else {
    return GsubLookup::Unsupported
  }
  if subtable_count == 0 {
    return GsubLookup::Unsupported
  }
  let singles : Array[GsubSingleSubst] = []
  let ligatures : Array[GsubLigatureSubst] = []
  for i = 0; i < subtable_count; i = i + 1 {
    let rel_off = lookup_off + 6 + i * 2
    guard opt_u16(data, rel_off) is Some(rel) else { continue }
    let subtable_off = lookup_off + rel
    if subtable_off + 4 > table_end {
      continue
    }
    match lookup_type {
      1 =>
        if parse_gsub_single(data, subtable_off, table_end) is Some(s) {
          singles.push(s)
        }
      4 =>
        if parse_gsub_ligature(data, subtable_off, table_end) is Some(l) {
          ligatures.push(l)
        }
      7 => {
        // Extension Substitution
        guard opt_u16(data, subtable_off) is Some(ext_format) else { continue }
        if ext_format != 1 {
          continue
        }
        if subtable_off + 8 > table_end {
          continue
        }
        guard opt_u16(data, subtable_off + 2) is Some(inner_lookup_type) else {
          continue
        }
        guard opt_u32(data, subtable_off + 4) is Some(inner_rel) else {
          continue
        }
        let inner_subtable_off = subtable_off + inner_rel
        if inner_subtable_off + 4 > table_end {
          continue
        }
        match inner_lookup_type {
          1 =>
            if parse_gsub_single(data, inner_subtable_off, table_end) is Some(s) {
              singles.push(s)
            }
          4 =>
            if parse_gsub_ligature(data, inner_subtable_off, table_end)
              is Some(l) {
              ligatures.push(l)
            }
          _ => ()
        }
      }
      _ => return GsubLookup::Unsupported
    }
  }
  if !singles.is_empty() {
    GsubLookup::Single(singles)
  } else if !ligatures.is_empty() {
    GsubLookup::Ligature(ligatures)
  } else {
    GsubLookup::Unsupported
  }
}

///|
fn parse_gsub_single(
  data : BytesView,
  subtable_off : Int32,
  table_end : Int32,
) -> GsubSingleSubst? {
  guard opt_u16(data, subtable_off) is Some(format) else { return None }
  guard opt_u16(data, subtable_off + 2) is Some(coverage_rel) else {
    return None
  }
  let coverage = parse_coverage(data, subtable_off + coverage_rel, table_end)
  match format {
    1 => {
      guard opt_i16(data, subtable_off + 4) is Some(delta) else { return None }
      Some({ coverage, format: DeltaGlyphID(delta), })
    }
    2 => {
      guard opt_u16(data, subtable_off + 4) is Some(glyph_count) else {
        return None
      }
      // GlyphCount は Coverage の glyph 数と一致する必要がある。
      if glyph_count != coverage.glyph_count() {
        return None
      }
      let subs_end = subtable_off + 6 + glyph_count * 2
      if subs_end > table_end {
        return None
      }
      let subs : Array[Int32] = []
      for i = 0; i < glyph_count; i = i + 1 {
        guard opt_u16(data, subtable_off + 6 + i * 2) is Some(g) else {
          return None
        }
        subs.push(g)
      }
      Some({ coverage, format: SubstituteGlyphIDs(subs), })
    }
    _ => None
  }
}

///|
fn parse_gsub_ligature(
  data : BytesView,
  subtable_off : Int32,
  table_end : Int32,
) -> GsubLigatureSubst? {
  guard opt_u16(data, subtable_off) is Some(format) else { return None }
  if format != 1 {
    return None
  }
  guard opt_u16(data, subtable_off + 2) is Some(coverage_rel) else {
    return None
  }
  let coverage = parse_coverage(data, subtable_off + coverage_rel, table_end)
  guard opt_u16(data, subtable_off + 4) is Some(ligature_set_count) else {
    return None
  }
  // LigatureSetCount は Coverage の glyph 数と一致する必要がある。
  if ligature_set_count != coverage.glyph_count() {
    return None
  }
  let ligature_sets : Array[Array[GsubLigature]] = []
  for i = 0; i < ligature_set_count; i = i + 1 {
    guard opt_u16(data, subtable_off + 6 + i * 2) is Some(set_rel) else {
      return None
    }
    let set_off = subtable_off + set_rel
    if set_off + 2 > table_end {
      return None
    }
    guard opt_u16(data, set_off) is Some(ligature_count) else { return None }
    let ligatures : Array[GsubLigature] = []
    for j = 0; j < ligature_count; j = j + 1 {
      guard opt_u16(data, set_off + 2 + j * 2) is Some(lig_rel) else {
        return None
      }
      let lig_off = set_off + lig_rel
      if lig_off + 4 > table_end {
        return None
      }
      guard opt_u16(data, lig_off) is Some(ligature_glyph) else { return None }
      guard opt_u16(data, lig_off + 2) is Some(component_count) else {
        return None
      }
      // component_count は合字を構成する全グリフ数 (1 番目 + 2 番目以降)。
      // 仕様上 2 以上である必要がある。不正値はスキップする。
      if component_count < 2 {
        continue
      }
      // component_count が残りバイト数の許容最大を超える場合は不正フォント
      // として ligature 全体を棄却する (DoS 耐性)。
      let remaining_after_header = table_end - (lig_off + 4)
      let max_component_count = remaining_after_header / 2 + 1
      if component_count > max_component_count {
        return None
      }
      let component_glyph_ids : Array[Int32] = []
      for k = 0; k < component_count - 1; k = k + 1 {
        let comp_off = lig_off + 4 + k * 2
        if comp_off + 2 > table_end {
          return None
        }
        guard opt_u16(data, comp_off) is Some(g) else { return None }
        component_glyph_ids.push(g)
      }
      ligatures.push({ ligature_glyph, component_glyph_ids, })
    }
    ligature_sets.push(ligatures)
  }
  Some({ coverage, ligature_sets, })
}

///|
/// GPOS Lookup をパースする (Type 1 Single / Type 2 Pair / Type 9 Extension)。
fn parse_gpos_lookup(
  data : BytesView,
  lookup_off : Int32,
  table_end : Int32,
) -> GposLookup {
  if lookup_off + 8 > table_end {
    return GposLookup::Unsupported
  }
  guard opt_u16(data, lookup_off) is Some(lookup_type) else {
    return GposLookup::Unsupported
  }
  guard opt_u16(data, lookup_off + 4) is Some(subtable_count) else {
    return GposLookup::Unsupported
  }
  if subtable_count == 0 {
    return GposLookup::Unsupported
  }
  let singles : Array[GposSingleAdjust] = []
  let pairs : Array[GposPairAdjust] = []
  for i = 0; i < subtable_count; i = i + 1 {
    let rel_off = lookup_off + 6 + i * 2
    guard opt_u16(data, rel_off) is Some(rel) else { continue }
    let subtable_off = lookup_off + rel
    if subtable_off + 4 > table_end {
      continue
    }
    match lookup_type {
      1 =>
        if parse_gpos_single(data, subtable_off, table_end) is Some(s) {
          singles.push(s)
        }
      2 =>
        if parse_gpos_pair(data, subtable_off, table_end) is Some(p) {
          pairs.push(p)
        }
      9 => {
        // Extension Positioning
        guard opt_u16(data, subtable_off) is Some(ext_format) else { continue }
        if ext_format != 1 {
          continue
        }
        if subtable_off + 8 > table_end {
          continue
        }
        guard opt_u16(data, subtable_off + 2) is Some(inner_lookup_type) else {
          continue
        }
        guard opt_u32(data, subtable_off + 4) is Some(inner_rel) else {
          continue
        }
        let inner_subtable_off = subtable_off + inner_rel
        if inner_subtable_off + 4 > table_end {
          continue
        }
        match inner_lookup_type {
          1 =>
            if parse_gpos_single(data, inner_subtable_off, table_end) is Some(s) {
              singles.push(s)
            }
          2 =>
            if parse_gpos_pair(data, inner_subtable_off, table_end) is Some(p) {
              pairs.push(p)
            }
          _ => ()
        }
      }
      _ => return GposLookup::Unsupported
    }
  }
  if !singles.is_empty() {
    GposLookup::Single(singles)
  } else if !pairs.is_empty() {
    GposLookup::Pair(pairs)
  } else {
    GposLookup::Unsupported
  }
}

///|
fn parse_gpos_single(
  data : BytesView,
  subtable_off : Int32,
  table_end : Int32,
) -> GposSingleAdjust? {
  guard opt_u16(data, subtable_off) is Some(format) else { return None }
  guard opt_u16(data, subtable_off + 2) is Some(coverage_rel) else {
    return None
  }
  let coverage = parse_coverage(data, subtable_off + coverage_rel, table_end)
  guard opt_u16(data, subtable_off + 4) is Some(value_format) else {
    return None
  }
  // Device Table オフセット (bits 4-7) までは読み飛ばすが、
  // それ以上の未知ビットは未対応とする。
  if (value_format & 0xFF00) != 0 {
    return None
  }
  let value_size = value_record_expected_size(value_format)
  match format {
    1 => {
      if subtable_off + 6 + value_size > table_end {
        return None
      }
      let (vr, advanced) = read_value_record(
        data,
        subtable_off + 6,
        value_format,
      )
      if advanced != value_size {
        return None
      }
      Some({ coverage, format: Uniform(vr), })
    }
    2 => {
      guard opt_u16(data, subtable_off + 6) is Some(value_count) else {
        return None
      }
      // Format 2 の ValueCount は Coverage の glyph 数と一致する必要がある。
      if value_count != coverage.glyph_count() {
        return None
      }
      if subtable_off + 8 + value_count * value_size > table_end {
        return None
      }
      let values : Array[ValueRecord] = []
      let mut cursor = subtable_off + 8
      for i = 0; i < value_count; i = i + 1 {
        let (vr, advanced) = read_value_record(data, cursor, value_format)
        if advanced != value_size {
          return None
        }
        values.push(vr)
        cursor = cursor + advanced
      }
      Some({ coverage, format: PerGlyph(values), })
    }
    _ => None
  }
}

///|
fn parse_gpos_pair(
  data : BytesView,
  subtable_off : Int32,
  table_end : Int32,
) -> GposPairAdjust? {
  guard opt_u16(data, subtable_off) is Some(format) else { return None }
  guard opt_u16(data, subtable_off + 2) is Some(coverage_rel) else {
    return None
  }
  let coverage = parse_coverage(data, subtable_off + coverage_rel, table_end)
  guard opt_u16(data, subtable_off + 4) is Some(value_format_1) else {
    return None
  }
  guard opt_u16(data, subtable_off + 6) is Some(value_format_2) else {
    return None
  }
  if (value_format_1 & 0xFF00) != 0 || (value_format_2 & 0xFF00) != 0 {
    return None
  }
  let value1_size = value_record_expected_size(value_format_1)
  let value2_size = value_record_expected_size(value_format_2)
  match format {
    1 => {
      guard opt_u16(data, subtable_off + 8) is Some(pair_set_count) else {
        return None
      }
      // Format 1 の PairSetCount は Coverage の glyph 数と一致する必要がある。
      if pair_set_count != coverage.glyph_count() {
        return None
      }
      if subtable_off + 10 + pair_set_count * 2 > table_end {
        return None
      }
      let sets : Array[Array[GposPair]] = []
      for i = 0; i < pair_set_count; i = i + 1 {
        guard opt_u16(data, subtable_off + 10 + i * 2) is Some(set_rel) else {
          return None
        }
        let set_off = subtable_off + set_rel
        if set_off + 2 > table_end {
          return None
        }
        guard opt_u16(data, set_off) is Some(pair_value_count) else {
          return None
        }
        // 各 PairValueRecord は second_glyph (2) + value1 + value2。
        let record_size = 2 + value1_size + value2_size
        // pair_value_count が残りバイト数の許容最大を超える場合、
        // 不正フォントとして PairSet 全体を棄却する (DoS 耐性)。
        let remaining_after_count = table_end - (set_off + 2)
        let max_pair_value_count = remaining_after_count / record_size
        if pair_value_count > max_pair_value_count {
          return None
        }
        let pairs : Array[GposPair] = []
        let mut cursor = set_off + 2
        for _i = 0; _i < pair_value_count; _i = _i + 1 {
          guard opt_u16(data, cursor) is Some(second_glyph) else { return None }
          let (value1, advanced1) = read_value_record(
            data,
            cursor + 2,
            value_format_1,
          )
          if advanced1 != value1_size {
            return None
          }
          let (value2, advanced2) = read_value_record(
            data,
            cursor + 2 + advanced1,
            value_format_2,
          )
          if advanced2 != value2_size {
            return None
          }
          pairs.push({ second_glyph, value1, value2, })
          cursor = cursor + 2 + advanced1 + advanced2
        }
        sets.push(pairs)
      }
      Some({ coverage, format: PairSet(sets), })
    }
    2 => {
      guard opt_u16(data, subtable_off + 8) is Some(rel_cd1) else {
        return None
      }
      guard opt_u16(data, subtable_off + 10) is Some(rel_cd2) else {
        return None
      }
      guard opt_u16(data, subtable_off + 12) is Some(class1_count) else {
        return None
      }
      guard opt_u16(data, subtable_off + 14) is Some(class2_count) else {
        return None
      }
      let class_def_1 = parse_class_def(data, subtable_off + rel_cd1, table_end)
      let class_def_2 = parse_class_def(data, subtable_off + rel_cd2, table_end)
      let total = class1_count * class2_count
      let record_size = value1_size + value2_size
      // 両方の valueFormat が 0 の場合レコードサイズは 0。
      // 空の records で early return し、値のないレコードを大量に作らない。
      if record_size == 0 {
        return Some({
          coverage,
          format: Class(class_def_1, class_def_2, class1_count, class2_count, []),
        })
      }
      let total_bytes = total * record_size
      if subtable_off + 16 + total_bytes > table_end {
        return None
      }
      let records : Array[(ValueRecord, ValueRecord)] = []
      let mut cursor = subtable_off + 16
      for _i = 0; _i < total; _i = _i + 1 {
        let (vr1, advanced1) = read_value_record(data, cursor, value_format_1)
        if advanced1 != value1_size {
          return None
        }
        cursor = cursor + advanced1
        let (vr2, advanced2) = read_value_record(data, cursor, value_format_2)
        if advanced2 != value2_size {
          return None
        }
        cursor = cursor + advanced2
        records.push((vr1, vr2))
      }
      Some({
        coverage,
        format: Class(
          class_def_1, class_def_2, class1_count, class2_count, records,
        ),
      })
    }
    _ => None
  }
}

///|
/// `value_format` のセットビット数に応じた ValueRecord の固定サイズを返す。
/// Device Table オフセット (bits 4-7) も 2 バイトずつ占有する。
fn value_record_expected_size(value_format : Int32) -> Int32 {
  let mut size = 0
  for bit = 0; bit < 8; bit = bit + 1 {
    if (value_format & (1 << bit)) != 0 {
      size = size + 2
    }
  }
  size
}

///|
/// Coverage テーブルをパースする (Format 1 / Format 2)。
/// 読み取り途中でデータが尽きた場合、それまでに読めたエントリを返す (寛容方針)。
fn parse_coverage(data : BytesView, off : Int32, table_end : Int32) -> Coverage {
  if off + 2 > table_end {
    return Coverage::GlyphList([])
  }
  guard opt_u16(data, off) is Some(format) else {
    return Coverage::GlyphList([])
  }
  match format {
    1 => {
      if off + 4 > table_end {
        return Coverage::GlyphList([])
      }
      guard opt_u16(data, off + 2) is Some(glyph_count) else {
        return Coverage::GlyphList([])
      }
      let glyphs : Array[Int32] = []
      for i = 0; i < glyph_count; i = i + 1 {
        let glyph_off = off + 4 + i * 2
        if glyph_off + 2 > table_end {
          return Coverage::GlyphList(glyphs)
        }
        guard opt_u16(data, glyph_off) is Some(g) else {
          return Coverage::GlyphList(glyphs)
        }
        glyphs.push(g)
      }
      Coverage::GlyphList(glyphs)
    }
    2 => {
      if off + 4 > table_end {
        return Coverage::RangeList([])
      }
      guard opt_u16(data, off + 2) is Some(range_count) else {
        return Coverage::RangeList([])
      }
      let ranges : Array[(Int32, Int32, Int32)] = []
      for i = 0; i < range_count; i = i + 1 {
        let base = off + 4 + i * 6
        if base + 6 > table_end {
          return Coverage::RangeList(ranges)
        }
        guard opt_u16(data, base) is Some(start) else {
          return Coverage::RangeList(ranges)
        }
        guard opt_u16(data, base + 2) is Some(end) else {
          return Coverage::RangeList(ranges)
        }
        guard opt_u16(data, base + 4) is Some(start_idx) else {
          return Coverage::RangeList(ranges)
        }
        ranges.push((start, end, start_idx))
      }
      Coverage::RangeList(ranges)
    }
    _ => Coverage::GlyphList([])
  }
}

///|
/// ClassDef テーブルをパースする (Format 1 / Format 2、寛容方針)。
fn parse_class_def(
  data : BytesView,
  off : Int32,
  table_end : Int32,
) -> ClassDef {
  if off + 2 > table_end {
    return ClassDef::Format2([])
  }
  guard opt_u16(data, off) is Some(format) else { return ClassDef::Format2([]) }
  match format {
    1 => {
      if off + 6 > table_end {
        return ClassDef::Format2([])
      }
      guard opt_u16(data, off + 2) is Some(start_glyph) else {
        return ClassDef::Format2([])
      }
      guard opt_u16(data, off + 4) is Some(glyph_count) else {
        return ClassDef::Format2([])
      }
      let class_values : Array[Int32] = []
      for i = 0; i < glyph_count; i = i + 1 {
        let class_off = off + 6 + i * 2
        if class_off + 2 > table_end {
          return ClassDef::Format1(start_glyph, class_values)
        }
        guard opt_u16(data, class_off) is Some(cv) else {
          return ClassDef::Format1(start_glyph, class_values)
        }
        class_values.push(cv)
      }
      ClassDef::Format1(start_glyph, class_values)
    }
    2 => {
      if off + 4 > table_end {
        return ClassDef::Format2([])
      }
      guard opt_u16(data, off + 2) is Some(range_count) else {
        return ClassDef::Format2([])
      }
      let ranges : Array[(Int32, Int32, Int32)] = []
      for i = 0; i < range_count; i = i + 1 {
        let base = off + 4 + i * 6
        if base + 6 > table_end {
          return ClassDef::Format2(ranges)
        }
        guard opt_u16(data, base) is Some(start) else {
          return ClassDef::Format2(ranges)
        }
        guard opt_u16(data, base + 2) is Some(end) else {
          return ClassDef::Format2(ranges)
        }
        guard opt_u16(data, base + 4) is Some(class_) else {
          return ClassDef::Format2(ranges)
        }
        ranges.push((start, end, class_))
      }
      ClassDef::Format2(ranges)
    }
    _ => ClassDef::Format2([])
  }
}

///|
/// GPOS ValueRecord を読み取る。
/// 戻り値は (ValueRecord, 消費バイト数)。途中でデータが尽きた場合、
/// それまでの値と消費数を返す (寛容方針)。呼び出し側が
/// `advanced == value_record_expected_size(value_format)` で完全性を検証する。
fn read_value_record(
  data : BytesView,
  off : Int32,
  value_format : Int32,
) -> (ValueRecord, Int32) {
  let vr = ValueRecord::default()
  let mut cursor = off
  if (value_format & 0x0001) != 0 {
    guard opt_i16(data, cursor) is Some(v) else { return (vr, cursor - off) }
    vr.x_placement = v
    cursor = cursor + 2
  }
  if (value_format & 0x0002) != 0 {
    guard opt_i16(data, cursor) is Some(v) else { return (vr, cursor - off) }
    vr.y_placement = v
    cursor = cursor + 2
  }
  if (value_format & 0x0004) != 0 {
    guard opt_i16(data, cursor) is Some(v) else { return (vr, cursor - off) }
    vr.x_advance = v
    cursor = cursor + 2
  }
  if (value_format & 0x0008) != 0 {
    guard opt_i16(data, cursor) is Some(v) else { return (vr, cursor - off) }
    vr.y_advance = v
    cursor = cursor + 2
  }
  // bits 4-7 (Device Table offsets) は読み飛ばし
  for bit = 4; bit < 8; bit = bit + 1 {
    if (value_format & (1 << bit)) != 0 {
      cursor = cursor + 2
    }
  }
  (vr, cursor - off)
}

// ---------------------------------------------------------------------------
// パース済みテーブル集合
// ---------------------------------------------------------------------------

///|
/// フォントファイルからパースした全テーブル情報。
struct ParsedTables {
  units_per_em : Int32
  num_glyphs : Int32
  ascent : Int32
  descent : Int32
  line_gap : Int32
  cap_height : Int32?
  x_height : Int32?
  loca_offsets : Array[Int32]
  glyf_offset : Int32
  glyf_length : Int32
  cmap : CmapLookup
  hmtx : HmtxTable
  gsub : GsubTable
  gpos : GposTable
}

///|
/// TTC ファイルから指定インデックスのフォントオフセットを取得する。
fn ttc_font_offset(data : BytesView, index : Int32) -> Int32 raise FontError {
  if data.length() < 12 {
    raise FontError::InvalidData("TTC header too short")
  }
  let num_fonts = be_u32(data, 8)
  if index >= num_fonts {
    raise FontError::InvalidData("TTC font index out of range")
  }
  let offset_pos = 12 + index * 4
  if offset_pos + 4 > data.length() {
    raise FontError::InvalidData("TTC offset table too short")
  }
  be_u32(data, offset_pos)
}

///|
/// フォントデータの全テーブルをパースする。
/// `index` は TTC (TrueType Collection) 内のフォントインデックス。
/// 単体フォントの場合は 0 を指定する。
fn parse_all(data : BytesView, index : Int32) -> ParsedTables raise FontError {
  // TTC ヘッダを検出し、指定インデックスのフォントオフセットを取得する
  let sfnt_start = if data.length() >= 4 && be_u32(data, 0) == TAG_TTCF {
    ttc_font_offset(data, index)
  } else {
    0
  }
  let dir = TableDirectory::parse(data, sfnt_start)
  let head_rec = dir.require(TAG_HEAD)
  let maxp_rec = dir.require(TAG_MAXP)
  let hhea_rec = dir.require(TAG_HHEA)
  let hmtx_rec = dir.require(TAG_HMTX)
  let loca_rec = dir.require(TAG_LOCA)
  let cmap_rec = dir.require(TAG_CMAP)
  let glyf_rec = dir.require(TAG_GLYF)
  let head = parse_head(data, head_rec)
  let num_glyphs = parse_maxp(data, maxp_rec)
  let hhea = parse_hhea(data, hhea_rec)
  let hmtx = parse_hmtx(data, hmtx_rec, hhea.number_of_h_metrics, num_glyphs)
  let loca_offsets = parse_loca(
    data,
    loca_rec,
    num_glyphs,
    head.index_to_loc_format,
  )
  let cmap = parse_cmap(data, cmap_rec)
  let gsub = match dir.find(TAG_GSUB) {
    Some(rec) => parse_gsub(data, rec)
    None => GsubTable::empty()
  }
  let gpos = match dir.find(TAG_GPOS) {
    Some(rec) => parse_gpos(data, rec)
    None => GposTable::empty()
  }
  let os2 = match dir.find(TAG_OS2) {
    Some(rec) => parse_os2(data, rec)
    None => { cap_height: None, x_height: None, }
  }
  {
    units_per_em: head.units_per_em,
    num_glyphs,
    ascent: hhea.ascent,
    descent: hhea.descent,
    line_gap: hhea.line_gap,
    cap_height: os2.cap_height,
    x_height: os2.x_height,
    loca_offsets,
    glyf_offset: glyf_rec.offset,
    glyf_length: glyf_rec.length,
    cmap,
    hmtx,
    gsub,
    gpos,
  }
}
