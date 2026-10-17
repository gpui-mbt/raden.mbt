/// OpenType GSUB / GPOS シェーピングの適用ロジック。
/// 上流 src/font/shape.rs の移植。

///|
/// GSUB Lookup (Single Substitution / Ligature Substitution) を適用する。
/// `parse_gsub` 時点で重複は除去済みのため、ここでは feature 有効判定のみ行う。
fn apply_gsub(
  gsub : GsubTable,
  buf : GlyphBuffer,
  features : FontFeatureSettings,
  font : Font,
) -> Unit {
  for a in gsub.applicable_lookups {
    let (tag, idx) = a
    let enabled = if tag == TAG_LIGA {
      features.liga
    } else if tag == TAG_CLIG {
      features.clig
    } else {
      false
    }
    if !enabled {
      continue
    }
    if gsub.lookup_at(idx) is Some(lookup) {
      apply_gsub_lookup(lookup, buf, font)
    }
  }
}

///|
fn apply_gsub_lookup(
  lookup : GsubLookup,
  buf : GlyphBuffer,
  font : Font,
) -> Unit {
  match lookup {
    GsubLookup::Single(singles) =>
      for s in singles {
        apply_gsub_single(s, buf, font)
      }
    GsubLookup::Ligature(ligatures) =>
      for l in ligatures {
        apply_gsub_ligature(l, buf, font)
      }
    GsubLookup::Unsupported => ()
  }
}

///|
fn apply_gsub_single(
  s : GsubSingleSubst,
  buf : GlyphBuffer,
  font : Font,
) -> Unit {
  for i = 0; i < buf.glyph_ids.length(); i = i + 1 {
    let glyph_id = buf.glyph_ids[i]
    guard s.coverage.index_of(glyph_id) is Some(ci) else { continue }
    let new_gid = match s.format {
      DeltaGlyphID(d) =>
        // Microsoft OpenType Spec GSUB Type 1 Format 1 は modulo 65536 wrap を仕様化。
        // Int 加算後の & 0xFFFF は natural wrap と等価。
        (glyph_id + d) & 0xFFFF
      SubstituteGlyphIDs(subs) =>
        if ci < 0 || ci >= subs.length() {
          continue
        } else {
          subs[ci]
        }
    }
    buf.glyph_ids[i] = new_gid
    buf.placements_[i].advance = font.glyph_advance(new_gid)
  }
}

///|
fn apply_gsub_ligature(
  l : GsubLigatureSubst,
  buf : GlyphBuffer,
  font : Font,
) -> Unit {
  let mut i = 0
  while i < buf.length() {
    guard l.coverage.index_of(buf.glyph_ids[i]) is Some(ci) else {
      i = i + 1
      continue
    }
    guard ci < l.ligature_sets.length() else {
      i = i + 1
      continue
    }
    let ligatures = l.ligature_sets[ci]
    // 各 Ligature を順に試し、マッチするものの中で最長の component 数を持つ
    // ものを採用する。Microsoft OpenType spec GSUB Lookup Type 4 は
    // LigatureSet 内を "preference order" で格納することを規定しているが、
    // すべてのフォントが longest match 順を保証するとは限らないため、
    // 実装側で最長マッチを選択することで正しいシェーピング結果を得る。
    let mut matched : GsubLigature? = None
    for lig in ligatures {
      let n = lig.component_glyph_ids.length()
      // i + 1 + n のオーバーフローは Int 64bit では実質起きないが
      // end > buf.length() の範囲チェックで同等に防御される。
      let end = i + 1 + n
      if end > buf.length() {
        continue
      }
      let mut matches = true
      for k = 0; k < n; k = k + 1 {
        if buf.glyph_ids[i + 1 + k] != lig.component_glyph_ids[k] {
          matches = false
          break
        }
      }
      if matches {
        match matched {
          Some(m) if m.component_glyph_ids.length() >= n => ()
          _ => matched = Some(lig)
        }
      }
    }
    guard matched is Some(lig) else {
      i = i + 1
      continue
    }
    let consumed = 1 + lig.component_glyph_ids.length()
    let drain_end = i + consumed
    let ligature_glyph = lig.ligature_glyph
    buf.glyph_ids[i] = ligature_glyph
    buf.placements_[i] = {
      offset_x: 0.0,
      offset_y: 0.0,
      advance: font.glyph_advance(ligature_glyph),
    }
    // i+1..drain_end を 3 配列同期 drain で削除
    buf.drain_range(i + 1, drain_end)
    // cluster[i] は元の最初の char の index のまま (HarfBuzz 慣行)
    i = i + 1
  }
}

///|
/// GPOS `kern` feature 紐付き Lookup を適用する。
/// Microsoft 形式の古い `kern` テーブル (v0) ではなく、GPOS Pair Adjustment
/// 由来のカーニングのみを扱う。
fn apply_gpos_kern_feature_lookups(
  gpos : GposTable,
  buf : GlyphBuffer,
  font : Font,
) -> Unit {
  let scale = font.scale
  for idx in gpos.kern_lookups {
    if gpos.lookup_at(idx) is Some(lookup) {
      apply_gpos_lookup(lookup, buf, scale)
    }
  }
}

///|
fn apply_gpos_lookup(
  lookup : GposLookup,
  buf : GlyphBuffer,
  scale : Double,
) -> Unit {
  match lookup {
    GposLookup::Single(singles) =>
      for s in singles {
        apply_gpos_single(s, buf, scale)
      }
    GposLookup::Pair(pairs) =>
      for p in pairs {
        apply_gpos_pair(p, buf, scale)
      }
    GposLookup::Unsupported => ()
  }
}

///|
fn apply_gpos_single(
  s : GposSingleAdjust,
  buf : GlyphBuffer,
  scale : Double,
) -> Unit {
  for i = 0; i < buf.length(); i = i + 1 {
    guard s.coverage.index_of(buf.glyph_ids[i]) is Some(ci) else { continue }
    let vr = match s.format {
      Uniform(vr) => vr
      PerGlyph(vrs) =>
        if ci < 0 || ci >= vrs.length() {
          continue
        } else {
          vrs[ci]
        }
    }
    apply_value_record_to_placement(vr, buf.placements_[i], scale)
  }
}

///|
fn apply_gpos_pair(
  p : GposPairAdjust,
  buf : GlyphBuffer,
  scale : Double,
) -> Unit {
  for i = 0; i < buf.length() - 1; i = i + 1 {
    let g1 = buf.glyph_ids[i]
    let g2 = buf.glyph_ids[i + 1]
    // 本実装では GPOS Pair Adjustment の value1 (g1 側) のみ適用する。
    // value2 (g2 側) は将来の拡張として保持している。
    if p.lookup(g1, g2) is Some((value1, _value2)) {
      apply_value_record_to_placement(value1, buf.placements_[i], scale)
    }
  }
}

///|
fn apply_value_record_to_placement(
  vr : ValueRecord,
  placement : GlyphPlacement,
  scale : Double,
) -> Unit {
  placement.offset_x = placement.offset_x + vr.x_placement.to_double() * scale
  placement.offset_y = placement.offset_y + vr.y_placement.to_double() * scale
  placement.advance = placement.advance + vr.x_advance.to_double() * scale
  // y_advance は水平テキスト前提のため無視
}
