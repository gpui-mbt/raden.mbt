///|
/// raden 移植版のエラー分類。
///
/// 上流が panic/assert で表現していた失敗を、安全なエラーに分類する。
/// 差分の詳細は `docs/known-differences.md` を参照。
pub(all) suberror RadenError {
  /// 非有限値・負の寸法・不正な引数など、呼び出し側の入力ミス。
  /// 上流で panic/assert になっていた入力をここに分類する。
  InvalidInput(String)
  /// 未実装のフォーマット・変換・機能を要求された。
  /// 黙った no-op にはせず、必ずエラーとして表面化する。
  UnsupportedFeature(String)
  /// 寸法×BPP・パス点数・再帰深度などのリソース上限超過。
  /// 上流が過大確保や OOM になっていた入力をここに分類する。
  ResourceLimit(String)
}

///|
/// エラー内容を Debug 風の `Variant("message")` 形式で表示する。
/// inspect スナップショット・ログ出力用。
pub impl Show for RadenError with fn output(self, l) {
  match self {
    InvalidInput(m) => {
      l.write_string("InvalidInput(")
      Show::output(m, l)
      l.write_char(')')
    }
    UnsupportedFeature(m) => {
      l.write_string("UnsupportedFeature(")
      Show::output(m, l)
      l.write_char(')')
    }
    ResourceLimit(m) => {
      l.write_string("ResourceLimit(")
      Show::output(m, l)
      l.write_char(')')
    }
  }
}

///|
pub extend RadenError with Show::{to_string, output}
