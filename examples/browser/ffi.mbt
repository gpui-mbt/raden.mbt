///|
/// ブラウザ向け JS export 層。
/// ES module から直接呼べる薄い facade。描画計算は行わず
/// examples/scenes に委譲する。
///
/// JS 側との契約 (marshal):
/// - `Bytes` は `Uint8Array` として受け渡しされる。
/// - `raise` 付き関数は例外を投げず `Result` オブジェクトを返す。
///   成功: `{ _0: Uint8Array }`、失敗: `{ _0: <error オブジェクト> }`。
///   JS 側は `r._0 instanceof Uint8Array` で成否を判定し、
///   失敗時は `error_message(r._0)` で表示用文字列を得る。
/// - `Int64` 引数は JS の `BigInt` で渡す。

///|
/// scene を描画して canonical RGBA8 (w*h*4) を返す。
/// 入力バリデーションはここで行い、失敗は Result.Err として
/// JS 側へ伝播する (throw にはならない)。
pub fn render_scene_rgba8(
  name : String,
  w : Int32,
  h : Int32,
  frame : Int64,
  fps : Int64,
) -> Bytes raise @raden.RadenError {
  let scene = @scenes.SceneName::parse(name)
  if fps <= 0L {
    raise @raden.InvalidInput("fps must be > 0")
  }
  if w <= 0 || h <= 0 || w > 4096 || h > 4096 {
    raise @raden.InvalidInput("invalid size \{w}x\{h} (1..4096)")
  }
  @scenes.render_to_rgba8(scene, w, h, @scenes.animation_t(frame, fps))
}

///|
/// Result.Err の payload を表示用文字列へ変換する。
/// JS 側は `render_scene_rgba8` の `_0` が `Uint8Array` でないときに
/// この関数へ渡してエラー内容を取得する。
pub fn error_message(e : @raden.RadenError) -> String {
  e.to_string()
}

///|
/// canonical バイト列の sha256 (UI の hash 表示・判定用)。
pub fn sha256_hex(bytes : Bytes) -> String {
  @sha256.sha256_hex(bytes[:])
}

///|
/// ビルド時点の target/toolchain 情報 (UI の診断表示用)。
pub fn candidate_info() -> String {
  "moonbit-candidate (js target)"
}
