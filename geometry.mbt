///|
/// 図形と矩形のジオメトリ型。上流 `api/context.rs` / `api/path.rs` の
/// パブリック構造体に対応する。

///|
/// 2D の点。上流 `api/path.rs` の `Point` に対応。
/// Path::translate / transform がフィールドを直接更新するため mut とする。
pub(all) struct Point {
  mut x : Double
  mut y : Double
} derive(Eq, Debug)

///|
pub fn Point::new(x : Double, y : Double) -> Point {
  { x, y, }
}

///|
/// 浮動小数点の矩形。(x, y) は左上、(w, h) はサイズ。
pub(all) struct Rect {
  x : Double
  y : Double
  w : Double
  h : Double
} derive(Debug)

///|
pub fn Rect::new(x : Double, y : Double, w : Double, h : Double) -> Rect {
  { x, y, w, h, }
}

///|
/// 円。(cx, cy) は中心、r は半径。
pub(all) struct Circle {
  cx : Double
  cy : Double
  r : Double
} derive(Debug)

///|
pub fn Circle::new(cx : Double, cy : Double, r : Double) -> Circle {
  { cx, cy, r, }
}

///|
/// 楕円。中心 (cx, cy)、半径 (rx, ry)。
pub(all) struct Ellipse {
  cx : Double
  cy : Double
  rx : Double
  ry : Double
} derive(Debug)

///|
pub fn Ellipse::new(
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
) -> Ellipse {
  { cx, cy, rx, ry, }
}

///|
/// 角丸矩形。
pub(all) struct RoundRect {
  x : Double
  y : Double
  w : Double
  h : Double
  rx : Double
  ry : Double
} derive(Debug)

///|
pub fn RoundRect::new(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  rx : Double,
  ry : Double,
) -> RoundRect {
  { x, y, w, h, rx, ry, }
}

///|
/// 三角形。
pub(all) struct Triangle {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
  x2 : Double
  y2 : Double
} derive(Debug)

///|
pub fn Triangle::new(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Triangle {
  { x0, y0, x1, y1, x2, y2, }
}

///|
/// 線分。(x0, y0) から (x1, y1) への線分。
pub(all) struct Line {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
} derive(Debug)

///|
pub fn Line::new(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Line {
  { x0, y0, x1, y1, }
}

///|
/// 円弧。Blend2D の `BLArc` と同一レイアウト。
///
/// - `(cx, cy)`: 中心
/// - `(rx, ry)`: X/Y 方向の半径 (楕円弧対応)
/// - `start`: 開始角度 (ラジアン、3 時方向が 0、時計回りが正)
/// - `sweep`: 掃引角度 (ラジアン、正が時計回り)
pub(all) struct Arc {
  cx : Double
  cy : Double
  rx : Double
  ry : Double
  start : Double
  sweep : Double
} derive(Debug)

///|
pub fn Arc::new(
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
  start : Double,
  sweep : Double,
) -> Arc {
  { cx, cy, rx, ry, start, sweep, }
}

///|
/// 整数の矩形 (クリッピング済み)。パッケージ内部専用。
/// clip_to_rect でフィールドを直接縮小するため mut とする。
priv struct BoxI {
  mut x0 : Int32
  mut y0 : Int32
  mut x1 : Int32
  mut y1 : Int32
}

///|
pub extend Point with Eq::{not_equal, equal}

///|
pub extend Point with @debug.Debug::{to_repr}

///|
pub extend Rect with @debug.Debug::{to_repr}

///|
pub extend Circle with @debug.Debug::{to_repr}

///|
pub extend Ellipse with @debug.Debug::{to_repr}

///|
pub extend RoundRect with @debug.Debug::{to_repr}

///|
pub extend Triangle with @debug.Debug::{to_repr}

///|
pub extend Line with @debug.Debug::{to_repr}

///|
pub extend Arc with @debug.Debug::{to_repr}
