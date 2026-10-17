///|
/// 2D アフィン変換行列。Blend2D の `BLMatrix2D` と同一レイアウト。
/// 上流 `api/matrix.rs` の `Matrix2D` に対応。
///
/// ```text
/// | m00  m01 |    x' = m00*x + m10*y + m20
/// | m10  m11 |    y' = m01*x + m11*y + m21
/// | m20  m21 |
/// ```
///
/// - `m00`, `m11`: スケール
/// - `m01`, `m10`: せん断
/// - `m20`, `m21`: 平行移動
/// - 合成: 後乗算 (`matrix = matrix * T`) — Blend2D / SVG / Canvas 互換
pub(all) struct Matrix2D {
  mut m00 : Double
  mut m01 : Double
  mut m10 : Double
  mut m11 : Double
  mut m20 : Double
  mut m21 : Double
} derive(Eq, Debug)

///|
/// 単位行列。
pub fn Matrix2D::identity() -> Matrix2D {
  { m00: 1.0, m01: 0.0, m10: 0.0, m11: 1.0, m20: 0.0, m21: 0.0, }
}

///|
/// 全要素を指定して行列を生成する。
pub fn Matrix2D::new(
  m00 : Double,
  m01 : Double,
  m10 : Double,
  m11 : Double,
  m20 : Double,
  m21 : Double,
) -> Matrix2D {
  { m00, m01, m10, m11, m20, m21, }
}

///|
/// 平行移動行列を生成する。
pub fn Matrix2D::translation(tx : Double, ty : Double) -> Matrix2D {
  { m00: 1.0, m01: 0.0, m10: 0.0, m11: 1.0, m20: tx, m21: ty, }
}

///|
/// スケーリング行列を生成する。
pub fn Matrix2D::scaling(sx : Double, sy : Double) -> Matrix2D {
  { m00: sx, m01: 0.0, m10: 0.0, m11: sy, m20: 0.0, m21: 0.0, }
}

///|
/// 回転行列を生成する。角度はラジアン。
pub fn Matrix2D::rotation(angle : Double) -> Matrix2D {
  let (s, c) = (@math.sin(angle), @math.cos(angle))
  { m00: c, m01: s, m10: -s, m11: c, m20: 0.0, m21: 0.0, }
}

///|
/// せん断行列を生成する。Blend2D の `makeSkewing` / `skew` と同様、引数は接線の係数。
///
/// `x' = x + kx * y`, `y' = y + ky * x`。
pub fn Matrix2D::skewing(kx : Double, ky : Double) -> Matrix2D {
  { m00: 1.0, m01: ky, m10: kx, m11: 1.0, m20: 0.0, m21: 0.0, }
}

///|
/// 単位行列かどうか判定する。
pub fn Matrix2D::is_identity(self : Matrix2D) -> Bool {
  self.m00 == 1.0 &&
  self.m01 == 0.0 &&
  self.m10 == 0.0 &&
  self.m11 == 1.0 &&
  self.m20 == 0.0 &&
  self.m21 == 0.0
}

///|
/// 後乗算で行列を合成する: `self * other`。
pub fn Matrix2D::multiply(self : Matrix2D, other : Matrix2D) -> Matrix2D {
  {
    m00: self.m00 * other.m00 + self.m01 * other.m10,
    m01: self.m00 * other.m01 + self.m01 * other.m11,
    m10: self.m10 * other.m00 + self.m11 * other.m10,
    m11: self.m10 * other.m01 + self.m11 * other.m11,
    m20: self.m20 * other.m00 + self.m21 * other.m10 + other.m20,
    m21: self.m20 * other.m01 + self.m21 * other.m11 + other.m21,
  }
}

///|
/// 点 (x, y) を変換する。
pub fn Matrix2D::map_point(
  self : Matrix2D,
  x : Double,
  y : Double,
) -> (Double, Double) {
  (
    self.m00 * x + self.m10 * y + self.m20,
    self.m01 * x + self.m11 * y + self.m21,
  )
}

///|
/// 平行移動を後乗算で適用する。
pub fn Matrix2D::translate(self : Matrix2D, tx : Double, ty : Double) -> Unit {
  self.m20 += tx
  self.m21 += ty
}

///|
/// スケーリングを後乗算で適用する。
pub fn Matrix2D::scale(self : Matrix2D, sx : Double, sy : Double) -> Unit {
  self.m00 *= sx
  self.m01 *= sy
  self.m10 *= sx
  self.m11 *= sy
  self.m20 *= sx
  self.m21 *= sy
}

///|
/// 回転を後乗算で適用する。角度はラジアン。
pub fn Matrix2D::rotate(self : Matrix2D, angle : Double) -> Unit {
  let (s, c) = (@math.sin(angle), @math.cos(angle))
  let m00 = self.m00 * c - self.m01 * s
  let m01 = self.m00 * s + self.m01 * c
  let m10 = self.m10 * c - self.m11 * s
  let m11 = self.m10 * s + self.m11 * c
  let m20 = self.m20 * c - self.m21 * s
  let m21 = self.m20 * s + self.m21 * c
  self.m00 = m00
  self.m01 = m01
  self.m10 = m10
  self.m11 = m11
  self.m20 = m20
  self.m21 = m21
}

///|
/// せん断を後乗算で適用する。`self = self * S(kx, ky)`。
pub fn Matrix2D::skew(self : Matrix2D, kx : Double, ky : Double) -> Unit {
  let r = self.multiply(Matrix2D::skewing(kx, ky))
  self.m00 = r.m00
  self.m01 = r.m01
  self.m10 = r.m10
  self.m11 = r.m11
  self.m20 = r.m20
  self.m21 = r.m21
}

///|
/// 指定した中心点まわりの回転を後乗算で適用する。角度はラジアン。
/// Blend2D の `rotate(angle, cx, cy)` に相当する。
/// `self = self * T(-cx,-cy) * R(angle) * T(cx,cy)` と等価。
pub fn Matrix2D::rotate_around(
  self : Matrix2D,
  angle : Double,
  cx : Double,
  cy : Double,
) -> Unit {
  let (s, c) = (@math.sin(angle), @math.cos(angle))
  let tx = cx * (1.0 - c) + cy * s
  let ty = cy * (1.0 - c) - cx * s
  let m00 = self.m00 * c - self.m01 * s
  let m01 = self.m00 * s + self.m01 * c
  let m10 = self.m10 * c - self.m11 * s
  let m11 = self.m10 * s + self.m11 * c
  let m20 = self.m20 * c - self.m21 * s + tx
  let m21 = self.m20 * s + self.m21 * c + ty
  self.m00 = m00
  self.m01 = m01
  self.m10 = m10
  self.m11 = m11
  self.m20 = m20
  self.m21 = m21
}

///|
/// 平行移動を前乗算で適用する。
/// Blend2D の `postTranslate(tx, ty)` に相当する。
/// `self = T(tx,ty) * self` と等価。
pub fn Matrix2D::post_translate(
  self : Matrix2D,
  tx : Double,
  ty : Double,
) -> Unit {
  self.m20 += tx * self.m00 + ty * self.m10
  self.m21 += tx * self.m01 + ty * self.m11
}

///|
/// スケーリングを前乗算で適用する。
/// Blend2D の `postScale(sx, sy)` に相当する。
/// `self = S(sx,sy) * self` と等価。
pub fn Matrix2D::post_scale(self : Matrix2D, sx : Double, sy : Double) -> Unit {
  self.m00 *= sx
  self.m01 *= sx
  self.m10 *= sy
  self.m11 *= sy
}

///|
/// 回転を前乗算で適用する。角度はラジアン。
/// Blend2D の `postRotate(angle)` に相当する。
/// `self = R(angle) * self` と等価。
pub fn Matrix2D::post_rotate(self : Matrix2D, angle : Double) -> Unit {
  let r = Matrix2D::rotation(angle).multiply(self)
  self.m00 = r.m00
  self.m01 = r.m01
  self.m10 = r.m10
  self.m11 = r.m11
  self.m20 = r.m20
  self.m21 = r.m21
}

///|
/// せん断を前乗算で適用する。
/// Blend2D の `postSkew(kx, ky)` に相当する。
/// `self = S(kx, ky) * self` と等価。
pub fn Matrix2D::post_skew(self : Matrix2D, kx : Double, ky : Double) -> Unit {
  let r = Matrix2D::skewing(kx, ky).multiply(self)
  self.m00 = r.m00
  self.m01 = r.m01
  self.m10 = r.m10
  self.m11 = r.m11
  self.m20 = r.m20
  self.m21 = r.m21
}

///|
/// 任意の行列を前乗算で適用する。
/// Blend2D の `postTransform(m)` に相当する。
/// `self = m * self` と等価。
pub fn Matrix2D::post_transform(self : Matrix2D, m : Matrix2D) -> Unit {
  let r = m.multiply(self)
  self.m00 = r.m00
  self.m01 = r.m01
  self.m10 = r.m10
  self.m11 = r.m11
  self.m20 = r.m20
  self.m21 = r.m21
}

///|
/// 単位行列にリセットする。
pub fn Matrix2D::reset(self : Matrix2D) -> Unit {
  let r = Matrix2D::identity()
  self.m00 = r.m00
  self.m01 = r.m01
  self.m10 = r.m10
  self.m11 = r.m11
  self.m20 = r.m20
  self.m21 = r.m21
}

///|
/// 逆行列を計算する。行列式がほぼゼロの場合は None を返す。
pub fn Matrix2D::invert(self : Matrix2D) -> Matrix2D? {
  let det = self.m00 * self.m11 - self.m01 * self.m10
  if det.abs() < 0.0000000001 {
    return None
  }
  let inv_det = 1.0 / det
  Some({
    m00: self.m11 * inv_det,
    m01: -self.m01 * inv_det,
    m10: -self.m10 * inv_det,
    m11: self.m00 * inv_det,
    m20: (self.m10 * self.m21 - self.m11 * self.m20) * inv_det,
    m21: (self.m01 * self.m20 - self.m00 * self.m21) * inv_det,
  })
}

///|
pub extend Matrix2D with Eq::{not_equal, equal}

///|
pub extend Matrix2D with @debug.Debug::{to_repr}
