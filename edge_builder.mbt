///|
/// Path を線分に平坦化する EdgeBuilder。
/// 上流 `raster/edge_builder.rs` の移植。パッケージ内部専用。

///|
/// Blend2D 同等の平坦度閾値。
let flatness_tolerance : Double = 0.25

///|
/// de Casteljau 再帰分割の最大深度。
let max_recursion_depth : Int32 = 16

///|
/// エッジ (x0, y0, x1, y1) の型エイリアス。
type Edge = (Double, Double, Double, Double)

///|
/// Path を平坦化し、各線分を `out` に追加する。
/// `f` クロージャではなく出力バッファを直接受け取る形にしている。
fn flatten_path(path : Path, out : Array[Edge]) -> Unit raise RadenError {
  let cmds = path.cmds()
  let points = path.points()
  let conic_w = path.conic_weights()

  // 非有限座標を `InvalidInput` として弾く。
  // 上流は NaN 座標を検証せず不定な出力になるため、移植版では
  // 明示エラーとする (docs/known-differences.md 参照)。
  for p in points {
    if p.x.is_nan() || p.x.is_inf() || p.y.is_nan() || p.y.is_inf() {
      raise InvalidInput("path contains non-finite coordinates")
    }
  }

  let mut pt_idx = 0
  let mut conic_idx = 0

  // サブパス開始点 (Close で戻る先)
  let mut start : Point = { x: 0.0, y: 0.0, }
  // 現在の点
  let mut cur : Point = { x: 0.0, y: 0.0, }

  for cmd in cmds {
    match cmd {
      MoveTo => {
        let p = points[pt_idx]
        pt_idx += 1
        start = { x: p.x, y: p.y, }
        cur = { x: p.x, y: p.y, }
      }
      LineTo => {
        let p = points[pt_idx]
        pt_idx += 1
        out.push((cur.x, cur.y, p.x, p.y))
        cur = { x: p.x, y: p.y, }
      }
      CubicTo => {
        let cp1 = points[pt_idx]
        let cp2 = points[pt_idx + 1]
        let end = points[pt_idx + 2]
        pt_idx += 3
        flatten_cubic(out, cur, cp1, cp2, end, 0)
        cur = { x: end.x, y: end.y, }
      }
      QuadTo => {
        let cp = points[pt_idx]
        let end = points[pt_idx + 1]
        pt_idx += 2
        flatten_quadratic(out, cur, cp, end, 0)
        cur = { x: end.x, y: end.y, }
      }
      ConicTo => {
        let cp = points[pt_idx]
        let end = points[pt_idx + 1]
        pt_idx += 2
        let w = conic_w[conic_idx]
        conic_idx += 1
        flatten_conic(out, cur, cp, end, w)
        cur = { x: end.x, y: end.y, }
      }
      Close =>
        if cur.x != start.x || cur.y != start.y {
          out.push((cur.x, cur.y, start.x, start.y))
          cur = { x: start.x, y: start.y, }
        }
    }
  }
}

///|
/// 円錐曲線 (有理二次) を線分列で近似する。
fn flatten_conic(
  out : Array[Edge],
  p0 : Point,
  p1 : Point,
  p2 : Point,
  w : Double,
) -> Unit {
  let n = 24
  let mut prev = eval_conic(p0, p1, p2, w, 0.0)
  for i in 1..<=n {
    let t = i.to_double() / n.to_double()
    let next = eval_conic(p0, p1, p2, w, t)
    out.push((prev.x, prev.y, next.x, next.y))
    prev = next
  }
}

///|
fn eval_conic(
  p0 : Point,
  p1 : Point,
  p2 : Point,
  w : Double,
  t : Double,
) -> Point {
  let u = 1.0 - t
  let denom = u * u + 2.0 * w * u * t + t * t
  let x = (u * u * p0.x + 2.0 * w * u * t * p1.x + t * t * p2.x) / denom
  let y = (u * u * p0.y + 2.0 * w * u * t * p1.y + t * t * p2.y) / denom
  { x, y, }
}

///|
/// 3 次ベジェ曲線を de Casteljau で再帰的に平坦化する。
fn flatten_cubic(
  out : Array[Edge],
  p0 : Point,
  p1 : Point,
  p2 : Point,
  p3 : Point,
  depth : Int32,
) -> Unit {
  if depth >= max_recursion_depth || is_flat_cubic(p0, p1, p2, p3) {
    out.push((p0.x, p0.y, p3.x, p3.y))
    return
  }

  // de Casteljau t=0.5 分割
  let m01 = mid(p0, p1)
  let m12 = mid(p1, p2)
  let m23 = mid(p2, p3)
  let m012 = mid(m01, m12)
  let m123 = mid(m12, m23)
  let m0123 = mid(m012, m123)

  flatten_cubic(out, p0, m01, m012, m0123, depth + 1)
  flatten_cubic(out, m0123, m123, m23, p3, depth + 1)
}

///|
/// 制御点 p1, p2 が始点-終点直線に十分近いかを判定する (外積ベース)。
fn is_flat_cubic(p0 : Point, p1 : Point, p2 : Point, p3 : Point) -> Bool {
  let dx = p3.x - p0.x
  let dy = p3.y - p0.y
  let len_sq = dx * dx + dy * dy

  if len_sq < 0.000000000001 {
    // 始点と終点がほぼ同じ場合は制御点までの距離で判定
    let d1_sq = (p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y)
    let d2_sq = (p2.x - p0.x) * (p2.x - p0.x) + (p2.y - p0.y) * (p2.y - p0.y)
    let tol_sq = flatness_tolerance * flatness_tolerance
    return d1_sq <= tol_sq && d2_sq <= tol_sq
  }

  // cp1, cp2 から始点-終点直線への距離の 2 乗
  let cross1 = (p1.x - p0.x) * dy - (p1.y - p0.y) * dx
  let cross2 = (p2.x - p0.x) * dy - (p2.y - p0.y) * dx
  let tol_sq = flatness_tolerance * flatness_tolerance * len_sq

  cross1 * cross1 <= tol_sq && cross2 * cross2 <= tol_sq
}

///|
/// 2 次ベジェ曲線を de Casteljau で再帰的に平坦化する。
fn flatten_quadratic(
  out : Array[Edge],
  p0 : Point,
  p1 : Point,
  p2 : Point,
  depth : Int32,
) -> Unit {
  if depth >= max_recursion_depth || is_flat_quad(p0, p1, p2) {
    out.push((p0.x, p0.y, p2.x, p2.y))
    return
  }

  // de Casteljau t=0.5 分割
  let m01 = mid(p0, p1)
  let m12 = mid(p1, p2)
  let m012 = mid(m01, m12)

  flatten_quadratic(out, p0, m01, m012, depth + 1)
  flatten_quadratic(out, m012, m12, p2, depth + 1)
}

///|
/// 制御点 p1 が始点-終点直線に十分近いかを判定する (外積ベース)。
fn is_flat_quad(p0 : Point, p1 : Point, p2 : Point) -> Bool {
  let dx = p2.x - p0.x
  let dy = p2.y - p0.y
  let len_sq = dx * dx + dy * dy

  if len_sq < 0.000000000001 {
    let d_sq = (p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y)
    return d_sq <= flatness_tolerance * flatness_tolerance
  }

  let cross = (p1.x - p0.x) * dy - (p1.y - p0.y) * dx
  let tol_sq = flatness_tolerance * flatness_tolerance * len_sq
  cross * cross <= tol_sq
}

///|
/// 2 点の中点を返す。
fn mid(a : Point, b : Point) -> Point {
  { x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5, }
}
