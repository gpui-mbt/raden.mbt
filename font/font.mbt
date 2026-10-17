/// フォント公開 API。
///
/// FontData / FontFace / Font / GlyphBuffer / FontFeatureSettings /
/// TextMetrics / GlyphBounds を提供する。上流 src/font/mod.rs の移植。
/// ファイル読み込みは host 層の責務 (from_bytes のみ提供)。

///|
/// フォントエラー。
pub(all) suberror FontError {
  /// I/O 相当 (ファイル読み込み失敗等。メッセージのみ保持)。
  Io(String)
  /// フォントデータの構造不正。
  InvalidData(String)
}

///|
/// フォントファイルのバイトデータ。
pub struct FontData {
  data : Bytes
}

///|
/// バイト列からフォントデータを作成する。
/// (上流 `FontData::from_file` は host 層でファイルを読み `from_bytes` へ渡す構成とする)
pub fn FontData::from_bytes(bytes : Bytes) -> FontData {
  { data: bytes, }
}

///|
pub fn FontData::data(self : FontData) -> Bytes {
  self.data
}

///|
/// パース済みフォントフェイス。フォントデータから解析された情報を保持する。
pub struct FontFace {
  data : Bytes
  tables : ParsedTables
}

///|
/// FontData からフォントフェイスを作成する。
/// `index` は TTC 内のフォントインデックス。単体フォントの場合は 0。
pub fn FontFace::from_data(
  font_data : FontData,
  index : Int32,
) -> FontFace raise FontError {
  let tables = parse_all(font_data.data[:], index)
  { data: font_data.data, tables, }
}

///|
pub fn FontFace::units_per_em(self : FontFace) -> Int32 {
  self.tables.units_per_em
}

///|
pub fn FontFace::ascent(self : FontFace) -> Int32 {
  self.tables.ascent
}

///|
pub fn FontFace::descent(self : FontFace) -> Int32 {
  self.tables.descent
}

///|
pub fn FontFace::line_gap(self : FontFace) -> Int32 {
  self.tables.line_gap
}

///|
/// OS/2 テーブル v2 以上の sCapHeight (デザインユニット)。
/// 不在条件は上流 doc と同じ。
pub fn FontFace::cap_height(self : FontFace) -> Int32? {
  self.tables.cap_height
}

///|
/// OS/2 テーブル v2 以上の sxHeight (デザインユニット)。
pub fn FontFace::x_height(self : FontFace) -> Int32? {
  self.tables.x_height
}

///|
/// グリフ境界ボックス (デザインユニット、Y up、baseline 原点)。
/// 空グリフ / glyph_id 範囲外 / glyf 範囲外 / ヘッダ不足 /
/// Compound Glyph bbox が (0,0,0,0) のいずれかで None を返す (寛容方針)。
pub fn FontFace::glyph_bounds(
  self : FontFace,
  glyph_id : Int32,
) -> GlyphBounds? {
  guard glyph_entry_slice_opt(glyph_id, self.tables, self.data[:]) is Some(gd) else {
    return None
  }
  guard glyph_bbox_raw(gd) is Some(raw) else { return None }
  Some(GlyphBounds::from_raw_scaled(raw, 1.0))
}

///|
/// サイズ指定済みフォント。描画に使用する。
pub struct Font {
  face : FontFace
  size : Double
  scale : Double
  mut feature_settings : FontFeatureSettings
}

///|
/// FontFace とサイズ・feature 設定からフォントを作成する。
pub fn Font::with_features(
  face : FontFace,
  size : Double,
  features : FontFeatureSettings,
) -> Font {
  {
    face,
    size,
    scale: size / face.tables.units_per_em.to_double(),
    feature_settings: features,
  }
}

///|
/// FontFace とサイズからフォントを作成する。
pub fn Font::from_face(face : FontFace, size : Double) -> Font {
  Font::with_features(face, size, FontFeatureSettings::default())
}

///|
pub fn Font::size(self : Font) -> Double {
  self.size
}

///|
pub fn Font::scale(self : Font) -> Double {
  self.scale
}

///|
/// 文字 (Unicode コードポイント) をグリフ ID にマッピングする。
pub fn Font::map_char_to_glyph(self : Font, ch : Char) -> Int32 {
  self.face.tables.cmap.map(ch.to_int())
}

///|
/// グリフの水平アドバンス幅 (ピクセル単位) を返す。
pub fn Font::glyph_advance(self : Font, glyph_id : Int32) -> Double {
  let aws = self.face.tables.hmtx.advance_widths
  let aw = if glyph_id >= 0 && glyph_id < aws.length() {
    aws[glyph_id]
  } else {
    0
  }
  aw.to_double() * self.scale
}

///|
/// グリフのアウトラインを Path に追加する。
pub fn Font::append_glyph_outline(
  self : Font,
  glyph_id : Int32,
  offset_x : Double,
  offset_y : Double,
  path : @raden.Path,
) -> Unit raise FontError {
  append_glyph_outline(
    glyph_id,
    offset_x,
    offset_y,
    self.scale,
    self.face.tables,
    self.face.data[:],
    path,
  )
}

///|
/// アセント (ピクセル単位)。
pub fn Font::ascent(self : Font) -> Double {
  self.face.tables.ascent.to_double() * self.scale
}

///|
/// ディセント (ピクセル単位、負値)。
pub fn Font::descent(self : Font) -> Double {
  self.face.tables.descent.to_double() * self.scale
}

///|
/// 行間 (ピクセル単位)。
pub fn Font::line_gap(self : Font) -> Double {
  self.face.tables.line_gap.to_double() * self.scale
}

///|
/// cap_height のスケール済み値 (ピクセル単位)。
pub fn Font::cap_height(self : Font) -> Double? {
  self.tables_cap_height().map(fn(v) { v.to_double() * self.scale })
}

///|
fn Font::tables_cap_height(self : Font) -> Int32? {
  self.face.tables.cap_height
}

///|
/// x_height のスケール済み値 (ピクセル単位)。
pub fn Font::x_height(self : Font) -> Double? {
  match self.face.tables.x_height {
    Some(v) => Some(v.to_double() * self.scale)
    None => None
  }
}

///|
/// グリフ境界ボックス (スケール済みピクセル単位、Y up、baseline 原点)。
/// 描画時の Y 反転は適用しない (問い合わせ API)。
pub fn Font::glyph_bounds(self : Font, glyph_id : Int32) -> GlyphBounds? {
  guard glyph_entry_slice_opt(glyph_id, self.face.tables, self.face.data[:])
    is Some(gd) else {
    return None
  }
  guard glyph_bbox_raw(gd) is Some(raw) else { return None }
  Some(GlyphBounds::from_raw_scaled(raw, self.scale))
}

///|
/// 現在の feature 設定を変更する。
pub fn Font::set_feature_settings(
  self : Font,
  features : FontFeatureSettings,
) -> Unit {
  self.feature_settings = features
}

///|
/// 現在の feature 設定を返す。
pub fn Font::feature_settings(self : Font) -> FontFeatureSettings {
  self.feature_settings
}

///|
/// 同じ FontFace / size を持ち、feature 設定だけ異なる Font を複製する。
pub fn Font::clone_with_features(
  self : Font,
  features : FontFeatureSettings,
) -> Font {
  {
    face: self.face,
    size: self.size,
    scale: self.scale,
    feature_settings: features,
  }
}

///|
/// 新規 GlyphBuffer に shape 結果を入れて返す。
pub fn Font::shape(self : Font, text : String) -> GlyphBuffer {
  let buf = GlyphBuffer::new()
  self.shape_into(text, buf)
  buf
}

///|
/// Char (Unicode スカラー値) の UTF-8 符号長。
/// 上流 `char_indices()` の byte index 再現に使う。
fn utf8_len(ch : Char) -> Int32 {
  let c = ch.to_int()
  if c < 0x80 {
    1
  } else if c < 0x800 {
    2
  } else if c < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// 既存 GlyphBuffer を再利用して shape する。
pub fn Font::shape_into(self : Font, text : String, buf : GlyphBuffer) -> Unit {
  buf.clear()
  // 1. cmap で text → グリフ ID 列に変換。
  //    cluster は上流 `char_indices()` に合わせた UTF-8 byte index。
  //    MoonBit の String は UTF-16 内部表現だが、Char ごとの UTF-8 符号長を
  //    累積することで上流と同じ byte index を再現する。
  let mut byte_idx = 0
  for ch in text {
    let gid = self.map_char_to_glyph(ch)
    buf.push_glyph(
      gid,
      { offset_x: 0.0, offset_y: 0.0, advance: self.glyph_advance(gid), },
      byte_idx,
    )
    byte_idx = byte_idx + utf8_len(ch)
  }
  // 2. GSUB 適用
  apply_gsub(self.face.tables.gsub, buf, self.feature_settings, self)
  // 3. GPOS 適用 (kern feature 有効時のみ)
  if self.feature_settings.kern {
    apply_gpos_kern_feature_lookups(self.face.tables.gpos, buf, self)
  }
}

///|
/// 文字列全体のスケール済み水平アドバンス幅と境界ボックスを計測する。
pub fn Font::measure_text(self : Font, text : String) -> TextMetrics {
  let buf = self.shape(text)
  let mut advance = 0.0
  for p in buf.placements() {
    advance = advance + p.advance
  }
  {
    advance,
    bounding_box: compute_bounding_box(buf, self),
    leading_bearing: compute_leading_bearing(buf, self),
    trailing_bearing: compute_trailing_bearing(buf, self),
  }
}

///|
/// グリフの境界ボックス (Y up、baseline 原点)。
/// FontFace::glyph_bounds からは font デザイン座標、
/// Font::glyph_bounds からはスケール済みピクセル単位が入る。
pub struct GlyphBounds {
  x_min : Double
  y_min : Double
  x_max : Double
  y_max : Double
}

///|
fn GlyphBounds::from_raw_scaled(
  raw : (Int32, Int32, Int32, Int32),
  scale : Double,
) -> GlyphBounds {
  let (x_min, y_min, x_max, y_max) = raw
  {
    x_min: x_min.to_double() * scale,
    y_min: y_min.to_double() * scale,
    x_max: x_max.to_double() * scale,
    y_max: y_max.to_double() * scale,
  }
}

///|
fn GlyphBounds::translated_x(self : GlyphBounds, dx : Double) -> GlyphBounds {
  {
    x_min: self.x_min + dx,
    y_min: self.y_min,
    x_max: self.x_max + dx,
    y_max: self.y_max,
  }
}

///|
fn GlyphBounds::translated_y(self : GlyphBounds, dy : Double) -> GlyphBounds {
  {
    x_min: self.x_min,
    y_min: self.y_min + dy,
    x_max: self.x_max,
    y_max: self.y_max + dy,
  }
}

///|
fn GlyphBounds::union(self : GlyphBounds, other : GlyphBounds) -> GlyphBounds {
  {
    x_min: @cmp.minimum(self.x_min, other.x_min),
    y_min: @cmp.minimum(self.y_min, other.y_min),
    x_max: @cmp.maximum(self.x_max, other.x_max),
    y_max: @cmp.maximum(self.y_max, other.y_max),
  }
}

///|
/// 文字列全体のメトリクス (ピクセル単位)。
pub struct TextMetrics {
  /// 文字列全体の水平アドバンス幅 (ピクセル単位)。
  advance : Double
  /// 文字列全体の bbox (Y up、baseline 原点、ピクセル単位)。
  /// 空文字列、または全ての glyph_bounds が None のときは None。
  bounding_box : GlyphBounds?
  /// 最初のグリフの左側ベアリング (ピクセル単位)。
  leading_bearing : Double
  /// 最後のグリフの右側ベアリング (ピクセル単位)。
  trailing_bearing : Double
}

///|
/// OpenType feature 設定。
/// 現状は GSUB / GPOS による基本シェーピングのみをサポートする。
/// Microsoft 形式の古い kern テーブル (v0) には非対応。
pub struct FontFeatureSettings {
  /// カーニング (GPOS Pair Adjustment) を有効にする。
  kern : Bool
  /// 標準合字 (liga) を有効にする。
  liga : Bool
  /// 文脈依存合字 (clig) を有効にする。
  clig : Bool
}

///|
pub fn FontFeatureSettings::default() -> FontFeatureSettings {
  // `Font::from_face` 経由で作られたフォントがデフォルトでシェーピングを
  // 有効にするため、全 feature ON をデフォルトとする (上流と同じ)。
  { kern: true, liga: true, clig: true, }
}

///|
/// 全 feature を無効にした設定を返す。
pub fn FontFeatureSettings::none() -> FontFeatureSettings {
  { kern: false, liga: false, clig: false, }
}

///|
/// `kern` feature の on/off を設定した新しいインスタンスを返す。
pub fn FontFeatureSettings::with_kern(
  self : FontFeatureSettings,
  enabled : Bool,
) -> FontFeatureSettings {
  { kern: enabled, liga: self.liga, clig: self.clig, }
}

///|
/// `liga` feature の on/off を設定した新しいインスタンスを返す。
pub fn FontFeatureSettings::with_liga(
  self : FontFeatureSettings,
  enabled : Bool,
) -> FontFeatureSettings {
  { kern: self.kern, liga: enabled, clig: self.clig, }
}

///|
/// `clig` feature の on/off を設定した新しいインスタンスを返す。
pub fn FontFeatureSettings::with_clig(
  self : FontFeatureSettings,
  enabled : Bool,
) -> FontFeatureSettings {
  { kern: self.kern, liga: self.liga, clig: enabled, }
}

///|
/// グリフ単位の配置情報。
pub struct GlyphPlacement {
  /// X 軸方向のオフセット (ピクセル単位)。
  mut offset_x : Double
  /// Y 軸方向のオフセット (ピクセル単位、Y up)。
  mut offset_y : Double
  /// 水平アドバンス (ピクセル単位)。
  mut advance : Double
}

///|
/// シェーピング結果を格納するバッファ。
/// `Font::shape` / `Font::shape_into` により生成された場合、
/// glyph_ids.length() == placements.length() == clusters.length() の
/// 事後条件を満たす。
pub struct GlyphBuffer {
  glyph_ids : Array[Int32]
  placements_ : Array[GlyphPlacement]
  clusters : Array[Int32]
}

///|
pub fn GlyphBuffer::new() -> GlyphBuffer {
  { glyph_ids: [], placements_: [], clusters: [], }
}

///|
/// グリフ数を返す。
pub fn GlyphBuffer::length(self : GlyphBuffer) -> Int32 {
  self.glyph_ids.length()
}

///|
/// バッファが空かどうかを返す。
pub fn GlyphBuffer::is_empty(self : GlyphBuffer) -> Bool {
  self.glyph_ids.is_empty()
}

///|
/// 指定インデックスのグリフ ID を返す。
pub fn GlyphBuffer::glyph_id(self : GlyphBuffer, index : Int32) -> Int32? {
  if index < 0 || index >= self.glyph_ids.length() {
    return None
  }
  Some(self.glyph_ids[index])
}

///|
/// 指定インデックスの配置情報を返す。
pub fn GlyphBuffer::placement(
  self : GlyphBuffer,
  index : Int32,
) -> GlyphPlacement? {
  if index < 0 || index >= self.placements_.length() {
    return None
  }
  Some(self.placements_[index])
}

///|
/// 指定インデックスの cluster (UTF-8 byte index、上流 `char_indices` 互換) を返す。
pub fn GlyphBuffer::cluster(self : GlyphBuffer, index : Int32) -> Int32? {
  if index < 0 || index >= self.clusters.length() {
    return None
  }
  Some(self.clusters[index])
}

///|
/// (glyph_id, placement, cluster) を列挙する内部イテレーション。
fn GlyphBuffer::each(
  self : GlyphBuffer,
  f : (Int32, GlyphPlacement, Int32) -> Unit,
) -> Unit {
  for i = 0; i < self.glyph_ids.length(); i = i + 1 {
    f(self.glyph_ids[i], self.placements_[i], self.clusters[i])
  }
}

///|
/// 内部不変条件を検証する。
pub fn GlyphBuffer::is_well_formed(self : GlyphBuffer) -> Bool {
  self.glyph_ids.length() == self.placements_.length() &&
  self.placements_.length() == self.clusters.length()
}

///|
/// 3 配列を空にする。
fn GlyphBuffer::clear(self : GlyphBuffer) -> Unit {
  self.glyph_ids.clear()
  self.placements_.clear()
  self.clusters.clear()
}

///|
/// グリフ ID、配置、cluster を 1 組追加する。
fn GlyphBuffer::push_glyph(
  self : GlyphBuffer,
  glyph_id : Int32,
  placement : GlyphPlacement,
  cluster : Int32,
) -> Unit {
  self.glyph_ids.push(glyph_id)
  self.placements_.push(placement)
  self.clusters.push(cluster)
}

///|
/// 指定範囲 [start, end) の 3 配列を同時に削除する。
fn GlyphBuffer::drain_range(
  self : GlyphBuffer,
  start : Int32,
  end : Int32,
) -> Unit {
  // drain のない Array では in-place で詰める
  let n = end - start
  if n <= 0 {
    return
  }
  for i = start; i + n < self.glyph_ids.length(); i = i + 1 {
    self.glyph_ids[i] = self.glyph_ids[i + n]
    self.placements_[i] = self.placements_[i + n]
    self.clusters[i] = self.clusters[i + n]
  }
  let new_len = self.glyph_ids.length() - n
  self.glyph_ids.truncate(new_len)
  self.placements_.truncate(new_len)
  self.clusters.truncate(new_len)
}

///|
/// パッケージ内部用: placements のスライス相当アクセス。
fn GlyphBuffer::placements(self : GlyphBuffer) -> Array[GlyphPlacement] {
  self.placements_
}

///|
/// `GlyphBuffer` 全体の bbox を計算する (Y up、baseline 原点)。
/// 各グリフの glyph_bounds を「advance 累積 + placement offset」で
/// 平行移動し union を取る。glyph_id == 0 (.notdef) も含める。
fn compute_bounding_box(buffer : GlyphBuffer, font : Font) -> GlyphBounds? {
  let mut cursor_x = 0.0
  let mut bbox : GlyphBounds? = None
  buffer.each(fn(gid, placement, _cluster) {
    if font.glyph_bounds(gid) is Some(gb) {
      let translated = gb
        .translated_x(cursor_x + placement.offset_x)
        .translated_y(placement.offset_y)
      bbox = Some(
        match bbox {
          None => translated
          Some(b) => b.union(translated)
        },
      )
    }
    cursor_x = cursor_x + placement.advance
  })
  bbox
}

///|
/// 最初のグリフの左側ベアリングを計算する。
fn compute_leading_bearing(buffer : GlyphBuffer, font : Font) -> Double {
  if buffer.length() == 0 {
    return 0.0
  }
  let gid = buffer.glyph_ids[0]
  let placement = buffer.placements_[0]
  match font.glyph_bounds(gid) {
    Some(gb) => gb.x_min + placement.offset_x
    None => 0.0
  }
}

///|
/// 最後のグリフの右側ベアリングを計算する。
fn compute_trailing_bearing(buffer : GlyphBuffer, font : Font) -> Double {
  let n = buffer.length()
  if n == 0 {
    return 0.0
  }
  let gid = buffer.glyph_ids[n - 1]
  let placement = buffer.placements_[n - 1]
  match font.glyph_bounds(gid) {
    Some(gb) => placement.advance - placement.offset_x - gb.x_max
    None => 0.0
  }
}

// ---------------------------------------------------------------------------
// Context への描画接続 (上流 Context::fill_text / stroke_text 相当)
// ---------------------------------------------------------------------------

///|
/// テキストを 1 つの Path に展開する共通処理。
/// glyph_id == 0 はアウトラインを構築せず advance のみ加算する。
/// append_glyph_outline のエラーは握りつぶし、外部入力に対する
/// クラッシュ耐性を優先する (上流と同じく部分欠落を許容)。
fn build_text_path(
  x : Double,
  y : Double,
  font : Font,
  text : String,
  buf : GlyphBuffer,
) -> @raden.Path {
  let path = @raden.Path::new()
  font.shape_into(text, buf)
  let mut cursor_x = x
  for i = 0; i < buf.length(); i = i + 1 {
    let glyph_id = buf.glyph_ids[i]
    let placement = buf.placements_[i]
    if glyph_id != 0 {
      // GlyphPlacement::offset_y はフォント設計座標系 (Y up)、
      // append_glyph_outline は画面座標系 (Y down) を前提とするため、
      // 符号を反転して渡す。
      font.append_glyph_outline(
        glyph_id,
        cursor_x + placement.offset_x,
        y - placement.offset_y,
        path,
      ) catch {
        _ => ()
      }
    }
    cursor_x = cursor_x + placement.advance
  }
  path
}

///|
/// テキストを塗りつぶし描画する。
/// (x, y) はベースライン左端の位置。全グリフを 1 つの Path に結合し、
/// fill_path 1 回で一括描画する (上流と同じアプローチ)。
///
/// Context は raden ルートパッケージの型であり font パッケージから
/// メソッドを追加できないため、上流の `ctx.fill_text(x, y, font, text)` は
/// `font::fill_text(ctx, x, y, font, text)` の自由関数として提供する。
pub fn fill_text(
  ctx : @raden.Context,
  x : Double,
  y : Double,
  font : Font,
  text : String,
) -> Unit raise @raden.RadenError {
  let buf = GlyphBuffer::new()
  let path = build_text_path(x, y, font, text, buf)
  if !path.is_empty() {
    ctx.fill_path(path)
  }
}

///|
/// 文字列を現在の stroke 設定で描画する。
/// (x, y) はベースライン左端の位置。全グリフを 1 つの Path に結合し、
/// stroke_path 1 回で一括描画する。
pub fn stroke_text(
  ctx : @raden.Context,
  x : Double,
  y : Double,
  font : Font,
  text : String,
) -> Unit raise @raden.RadenError {
  let buf = GlyphBuffer::new()
  let path = build_text_path(x, y, font, text, buf)
  if !path.is_empty() {
    ctx.stroke_path(path)
  }
}
