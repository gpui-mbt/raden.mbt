/// グリフアウトライン → Path 変換。
///
/// glyf テーブルからグリフデータを読み出し、TrueType の 2 次ベジェアウトラインを
/// Path に変換する。Simple Glyph と Compound Glyph の両方に対応。
/// 上流 src/font/glyph.rs の移植。

///|
/// Compound Glyph の最大再帰深度。
const MAX_COMPOUND_DEPTH : Int32 = 16

// glyf フラグビット

///|
const ON_CURVE : Int32 = 0x01

///|
const X_SHORT : Int32 = 0x02

///|
const Y_SHORT : Int32 = 0x04

///|
const REPEAT_FLAG : Int32 = 0x08

///|
const X_SAME_OR_POS : Int32 = 0x10

///|
const Y_SAME_OR_POS : Int32 = 0x20

// Compound フラグビット

///|
const ARG_1_AND_2_ARE_WORDS : Int32 = 0x0001

///|
const ARGS_ARE_XY_VALUES : Int32 = 0x0002

///|
const WE_HAVE_A_SCALE : Int32 = 0x0008

///|
const MORE_COMPONENTS : Int32 = 0x0020

///|
const WE_HAVE_AN_X_AND_Y_SCALE : Int32 = 0x0040

///|
const WE_HAVE_A_TWO_BY_TWO : Int32 = 0x0080

///|
/// design units → pixel 変換パラメータ。
priv struct GlyphTransform {
  offset_x : Double
  offset_y : Double
  scale : Double
  m00 : Double
  m01 : Double
  m10 : Double
  m11 : Double
}

///|
fn GlyphTransform::new(
  offset_x : Double,
  offset_y : Double,
  scale : Double,
) -> GlyphTransform {
  { offset_x, offset_y, scale, m00: 1.0, m01: 0.0, m10: 0.0, m11: 1.0, }
}

///|
/// design units 座標をピクセル座標に変換する。
fn GlyphTransform::apply(
  self : GlyphTransform,
  x_design : Int32,
  y_design : Int32,
) -> (Double, Double) {
  let xd = x_design.to_double()
  let yd = y_design.to_double()
  let tx = xd * self.m00 + yd * self.m01
  let ty = xd * self.m10 + yd * self.m11
  (tx * self.scale + self.offset_x, -ty * self.scale + self.offset_y)
}

///|
/// グリフアウトラインを Path に追加する。
fn append_glyph_outline(
  glyph_id : Int32,
  offset_x : Double,
  offset_y : Double,
  scale : Double,
  tables : ParsedTables,
  data : BytesView,
  path : @raden.Path,
) -> Unit raise FontError {
  let xform = GlyphTransform::new(offset_x, offset_y, scale)
  append_glyph_recursive(glyph_id, xform, tables, data, path, 0)
}

///|
/// glyf テーブルから glyph_id のグリフデータスライスを取得する。
///
/// 戻り値:
/// - `Some(view)`: アウトライン入りグリフのスライス (10 バイト以上のヘッダを含む)。
/// - `None`: 空グリフ (`glyf_start == glyf_end`)。
/// - エラー: glyph_id 範囲外 / glyf 範囲外 / ヘッダ不足 (`glyph_data.length() < 10`)。
fn glyph_entry_slice(
  glyph_id : Int32,
  tables : ParsedTables,
  data : BytesView,
) -> BytesView? raise FontError {
  let gid = glyph_id
  if gid < 0 || gid + 1 >= tables.loca_offsets.length() {
    raise FontError::InvalidData("glyph id out of range")
  }
  let glyf_start = tables.loca_offsets[gid]
  let glyf_end = tables.loca_offsets[gid + 1]
  // 空グリフ (スペース等) は loca offset が等しい。
  if glyf_start == glyf_end {
    return None
  }
  let abs_start = tables.glyf_offset + glyf_start
  let abs_end = tables.glyf_offset + glyf_end
  if abs_start < 0 || abs_end > data.length() || abs_start >= abs_end {
    raise FontError::InvalidData("glyph data out of range")
  }
  let glyph_data = data[abs_start:abs_end]
  if glyph_data.length() < 10 {
    raise FontError::InvalidData("glyph header too short")
  }
  Some(glyph_data)
}

///|
/// グリフヘッダ 10 バイトから bbox を読み出す。
///
/// 戻り値: `(x_min, y_min, x_max, y_max)` の i16 4 値。
/// Compound Glyph (`number_of_contours < 0`) で bbox が `(0, 0, 0, 0)` のときは
/// `None` を返す (未計算のまま埋められた違反フォントを有効値と区別できないため)。
/// Simple Glyph では `(0, 0, 0, 0)` も有効値として `Some` を返す。
/// `glyph_data` の長さは `glyph_entry_slice` が 10 バイト以上を保証する。
fn glyph_bbox_raw(glyph_data : BytesView) -> (Int32, Int32, Int32, Int32)? {
  // glyph_data.length() >= 10 は呼び出し側が保証
  let number_of_contours = i16_of_u16(
    (glyph_data[0].to_int() << 8) | glyph_data[1].to_int(),
  )
  let x_min = i16_of_u16((glyph_data[2].to_int() << 8) | glyph_data[3].to_int())
  let y_min = i16_of_u16((glyph_data[4].to_int() << 8) | glyph_data[5].to_int())
  let x_max = i16_of_u16((glyph_data[6].to_int() << 8) | glyph_data[7].to_int())
  let y_max = i16_of_u16((glyph_data[8].to_int() << 8) | glyph_data[9].to_int())
  if number_of_contours < 0 &&
    x_min == 0 &&
    y_min == 0 &&
    x_max == 0 &&
    y_max == 0 {
    return None
  }
  Some((x_min, y_min, x_max, y_max))
}

///|
/// u16 ビットパターンを i16 値として解釈する。
fn i16_of_u16(v : Int32) -> Int32 {
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
/// 再帰的にグリフアウトラインを追加する (Compound 対応)。
fn append_glyph_recursive(
  glyph_id : Int32,
  xform : GlyphTransform,
  tables : ParsedTables,
  data : BytesView,
  path : @raden.Path,
  depth : Int32,
) -> Unit raise FontError {
  if depth > MAX_COMPOUND_DEPTH {
    raise FontError::InvalidData("compound glyph recursion too deep")
  }
  // glyph_id 範囲外 / glyf 範囲外 / ヘッダ不足のチェックは glyph_entry_slice 側に集約する。
  let glyph_data = match glyph_entry_slice(glyph_id, tables, data) {
    Some(slice) => slice
    // 空グリフ (スペース等) はアウトラインを追加せず正常終了する。
    None => return
  }
  let number_of_contours = be_i16(glyph_data, 0)
  if number_of_contours >= 0 {
    parse_simple_glyph(glyph_data, number_of_contours, xform, path)
  } else {
    parse_compound_glyph(glyph_data, xform, tables, data, path, depth)
  }
}

///|
/// Simple Glyph をパースして Path に変換する。
fn parse_simple_glyph(
  glyph_data : BytesView,
  number_of_contours : Int32,
  xform : GlyphTransform,
  path : @raden.Path,
) -> Unit raise FontError {
  if number_of_contours == 0 {
    return
  }
  // ヘッダ: number_of_contours(2) + xMin(2) + yMin(2) + xMax(2) + yMax(2) = 10 bytes
  let end_pts_off = 10
  let end_pts_end = end_pts_off + number_of_contours * 2
  if end_pts_end + 2 > glyph_data.length() {
    raise FontError::InvalidData("simple glyph contour data too short")
  }
  // end_pts_of_contours を読み出す
  let end_pts : Array[Int32] = []
  for i = 0; i < number_of_contours; i = i + 1 {
    end_pts.push(be_u16(glyph_data, end_pts_off + i * 2))
  }
  let num_points = end_pts[end_pts.length() - 1] + 1
  if num_points == 0 {
    return
  }
  // instruction_length + instructions をスキップ
  let instr_len = be_u16(glyph_data, end_pts_end)
  let flags_off = end_pts_end + 2 + instr_len
  if flags_off > glyph_data.length() {
    raise FontError::InvalidData("simple glyph instructions exceed data")
  }
  // フラグのデコード (repeat 対応)
  let flags : Array[Int32] = []
  let mut cursor = flags_off
  while flags.length() < num_points {
    if cursor >= glyph_data.length() {
      raise FontError::InvalidData("simple glyph flags truncated")
    }
    let flag = glyph_data[cursor].to_int()
    cursor = cursor + 1
    flags.push(flag)
    if (flag & REPEAT_FLAG) != 0 {
      if cursor >= glyph_data.length() {
        raise FontError::InvalidData("simple glyph repeat count truncated")
      }
      let repeat_count = glyph_data[cursor].to_int()
      cursor = cursor + 1
      for _i = 0; _i < repeat_count; _i = _i + 1 {
        if flags.length() >= num_points {
          break
        }
        flags.push(flag)
      }
    }
  }
  // X 座標のデコード (delta → 累積)
  let x_coords : Array[Int32] = []
  let mut x = 0
  for flag in flags {
    if (flag & X_SHORT) != 0 {
      if cursor >= glyph_data.length() {
        raise FontError::InvalidData("simple glyph x data truncated")
      }
      let dx = glyph_data[cursor].to_int()
      cursor = cursor + 1
      if (flag & X_SAME_OR_POS) != 0 {
        x = x + dx
      } else {
        x = x - dx
      }
    } else if (flag & X_SAME_OR_POS) == 0 {
      if cursor + 1 >= glyph_data.length() {
        raise FontError::InvalidData("simple glyph x data truncated")
      }
      let dx = i16_of_u16(
        (glyph_data[cursor].to_int() << 8) | glyph_data[cursor + 1].to_int(),
      )
      cursor = cursor + 2
      x = x + dx
    }
    // X_SAME_OR_POS && !X_SHORT → delta = 0, x unchanged
    x_coords.push(x)
  }
  // Y 座標のデコード (delta → 累積)
  let y_coords : Array[Int32] = []
  let mut y = 0
  for flag in flags {
    if (flag & Y_SHORT) != 0 {
      if cursor >= glyph_data.length() {
        raise FontError::InvalidData("simple glyph y data truncated")
      }
      let dy = glyph_data[cursor].to_int()
      cursor = cursor + 1
      if (flag & Y_SAME_OR_POS) != 0 {
        y = y + dy
      } else {
        y = y - dy
      }
    } else if (flag & Y_SAME_OR_POS) == 0 {
      if cursor + 1 >= glyph_data.length() {
        raise FontError::InvalidData("simple glyph y data truncated")
      }
      let dy = i16_of_u16(
        (glyph_data[cursor].to_int() << 8) | glyph_data[cursor + 1].to_int(),
      )
      cursor = cursor + 2
      y = y + dy
    }
    y_coords.push(y)
  }
  // contour ごとにパスを生成
  let mut contour_start = 0
  for end_pt in end_pts {
    let contour_end = end_pt + 1
    if contour_end > num_points || contour_start >= contour_end {
      contour_start = contour_end
      continue
    }
    emit_contour(
      flags[contour_start:contour_end],
      x_coords[contour_start:contour_end],
      y_coords[contour_start:contour_end],
      xform,
      path,
    )
    contour_start = contour_end
  }
}

///|
/// 1 つの contour を Path に変換する。
///
/// TrueType の 2 次ベジェ規則:
/// - on → on: line_to
/// - on → off → on: quad_to(off, on)
/// - off → off: 暗黙の on-curve (2 つの off-curve の中点) を挿入
fn emit_contour(
  flags : ArrayView[Int32],
  x_coords : ArrayView[Int32],
  y_coords : ArrayView[Int32],
  xform : GlyphTransform,
  path : @raden.Path,
) -> Unit {
  let n = flags.length()
  if n == 0 {
    return
  }
  let on_curve = fn(i : Int32) -> Bool { (flags[i] & ON_CURVE) != 0 }
  // 最初の on-curve 点を探す
  // すべて off-curve の場合は最初の 2 点の中点を開始点とする
  let (start_x, start_y, first_idx) = if on_curve(0) {
    let (sx, sy) = xform.apply(x_coords[0], y_coords[0])
    (sx, sy, 1)
  } else if on_curve(n - 1) {
    let (sx, sy) = xform.apply(x_coords[n - 1], y_coords[n - 1])
    (sx, sy, 0)
  } else {
    // 最初の 2 つの off-curve 点の中点
    let (x0, y0) = xform.apply(x_coords[0], y_coords[0])
    let (x1, y1) = xform.apply(x_coords[n - 1], y_coords[n - 1])
    ((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0)
  }
  path.move_to(start_x, start_y)
  let mut i = first_idx
  while i < n {
    if on_curve(i) {
      let (px, py) = xform.apply(x_coords[i], y_coords[i])
      path.line_to(px, py)
      i = i + 1
    } else {
      // off-curve 点
      let (cpx, cpy) = xform.apply(x_coords[i], y_coords[i])
      let next = (i + 1) % n
      if next == first_idx && first_idx == 0 && !on_curve(0) && !on_curve(n - 1) {
        // contour の終端に戻る (暗黙 on-curve = start)
        path.quad_to(cpx, cpy, start_x, start_y)
        i = i + 1
      } else if next < n && on_curve(next) {
        // off → on
        let (ex, ey) = xform.apply(x_coords[next], y_coords[next])
        path.quad_to(cpx, cpy, ex, ey)
        i = i + 2
      } else {
        // off → off: 暗黙 on-curve (中点)
        let (nx, ny) = xform.apply(x_coords[next], y_coords[next])
        let mid_x = (cpx + nx) * 0.5
        let mid_y = (cpy + ny) * 0.5
        path.quad_to(cpx, cpy, mid_x, mid_y)
        i = i + 1
      }
    }
  }
  // contour を閉じる
  path.close()
}

///|
/// Compound Glyph をパースする。
fn parse_compound_glyph(
  glyph_data : BytesView,
  xform : GlyphTransform,
  tables : ParsedTables,
  data : BytesView,
  path : @raden.Path,
  depth : Int32,
) -> Unit raise FontError {
  // ヘッダ 10 bytes をスキップ
  let mut cursor = 10
  while true {
    if cursor + 4 > glyph_data.length() {
      raise FontError::InvalidData("compound glyph truncated")
    }
    let comp_flags = be_u16(glyph_data, cursor)
    let glyph_index = be_u16(glyph_data, cursor + 2)
    cursor = cursor + 4
    // 引数 (オフセット)
    let (arg1, arg2) = if (comp_flags & ARG_1_AND_2_ARE_WORDS) != 0 {
      if cursor + 4 > glyph_data.length() {
        raise FontError::InvalidData("compound args truncated")
      }
      cursor = cursor + 4
      if (comp_flags & ARGS_ARE_XY_VALUES) != 0 {
        (
          be_i16(glyph_data, cursor - 4).to_double(),
          be_i16(glyph_data, cursor - 2).to_double(),
        )
      } else {
        (
          be_u16(glyph_data, cursor - 4).to_double(),
          be_u16(glyph_data, cursor - 2).to_double(),
        )
      }
    } else {
      if cursor + 2 > glyph_data.length() {
        raise FontError::InvalidData("compound args truncated")
      }
      cursor = cursor + 2
      if (comp_flags & ARGS_ARE_XY_VALUES) != 0 {
        (
          be_i8(glyph_data, cursor - 2).to_double(),
          be_i8(glyph_data, cursor - 1).to_double(),
        )
      } else {
        (
          be_u8(glyph_data, cursor - 2).to_double(),
          be_u8(glyph_data, cursor - 1).to_double(),
        )
      }
    }
    // 変換行列
    let mut cm00 = 1.0
    let mut cm01 = 0.0
    let mut cm10 = 0.0
    let mut cm11 = 1.0
    if (comp_flags & WE_HAVE_A_SCALE) != 0 {
      if cursor + 2 > glyph_data.length() {
        raise FontError::InvalidData("compound scale truncated")
      }
      let s = f2dot14(be_i16(glyph_data, cursor))
      cursor = cursor + 2
      cm00 = s
      cm11 = s
    } else if (comp_flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0 {
      if cursor + 4 > glyph_data.length() {
        raise FontError::InvalidData("compound xy scale truncated")
      }
      cm00 = f2dot14(be_i16(glyph_data, cursor))
      cm11 = f2dot14(be_i16(glyph_data, cursor + 2))
      cursor = cursor + 4
    } else if (comp_flags & WE_HAVE_A_TWO_BY_TWO) != 0 {
      if cursor + 8 > glyph_data.length() {
        raise FontError::InvalidData("compound 2x2 matrix truncated")
      }
      cm00 = f2dot14(be_i16(glyph_data, cursor))
      cm01 = f2dot14(be_i16(glyph_data, cursor + 2))
      cm10 = f2dot14(be_i16(glyph_data, cursor + 4))
      cm11 = f2dot14(be_i16(glyph_data, cursor + 6))
      cursor = cursor + 8
    }
    // 親の変換行列と合成
    let new_m00 = xform.m00 * cm00 + xform.m01 * cm10
    let new_m01 = xform.m00 * cm01 + xform.m01 * cm11
    let new_m10 = xform.m10 * cm00 + xform.m11 * cm10
    let new_m11 = xform.m10 * cm01 + xform.m11 * cm11
    // XY オフセットを親の変換行列でピクセル空間に変換
    let dx = if (comp_flags & ARGS_ARE_XY_VALUES) != 0 { arg1 } else { 0.0 }
    let dy = if (comp_flags & ARGS_ARE_XY_VALUES) != 0 { arg2 } else { 0.0 }
    let child_xform : GlyphTransform = {
      offset_x: xform.offset_x + (dx * xform.m00 + dy * xform.m01) * xform.scale,
      offset_y: xform.offset_y - (dx * xform.m10 + dy * xform.m11) * xform.scale,
      scale: xform.scale,
      m00: new_m00,
      m01: new_m01,
      m10: new_m10,
      m11: new_m11,
    }
    append_glyph_recursive(
      glyph_index,
      child_xform,
      tables,
      data,
      path,
      depth + 1,
    )
    if (comp_flags & MORE_COMPONENTS) == 0 {
      break
    }
  }
}

///|
/// F2Dot14 固定小数点数を Double に変換する。
fn f2dot14(value : Int32) -> Double {
  value.to_double() / 16384.0
}

///|
/// `glyph_entry_slice` のエラーを `None` に縮退させる寛容版。
/// `glyph_bounds` 等の問い合わせ API 用 (上流の `.ok()?` に相当)。
fn glyph_entry_slice_opt(
  glyph_id : Int32,
  tables : ParsedTables,
  data : BytesView,
) -> BytesView? {
  glyph_entry_slice(glyph_id, tables, data) catch {
    _ => None
  }
}
