---
id: RADEN-0002
status: open
priority: P1
milestone: M0
depends_on: [RADEN-0001]
---

# 固定Rust oracleと、誤って成功しない比較基盤を作る

## 目的

見た目の模倣ではなく、同じ入力に対するRust版とMoonBit版の描画結果・状態・エラーを比較する。描画実装に先行してRust側と比較器を作り、MoonBit実装の到着後にfixtureを順次有効化する。

## 実装方針

1. `conformance/rust-oracle/`を独立したRust CLIにする。`raden`はGit dependencyの`rev`または固定checkoutのpath dependencyでSHAを固定し、Cargo.lockを保存する。製品libraryやMoonBit consumerには依存させない。上流本体はread-onlyとする。
2. oracleは上流APIを実際に呼び、windowなしでraw pixel bufferとJSON metadataを出力する。`basic_drawing`の描画命令は同じ座標・順序・色で移し、SDL/raw_player表示はoracleへ持ち込まない。上流の図形描画を別言語で再実装してoracleと称さない。
3. 入力schema v1を定義する。`fixture_id / width / height / pixel_format / commands / seed / frame_index / fps / input_hash`を含め、数値型、有限値、単位、command順序を固定する。hash対象は正規化したpayloadとしhash自身を含めない。未知commandや未知enumはエラーにする。
4. 出力はcanonicalなチャンネル順のpremultiplied raw bytesとする。BGRA→RGBA等の並び替えは明記し、unpremultiplyや色空間変換をコア比較へ混ぜない。PNG/BMPは閲覧用で、ファイル圧縮差を不一致判定に使わない。
5. metadataにupstream SHA、oracle adapter SHA、candidate SHA、fixture/input hash、toolchain、target、OS/arch、寸法、stride、alpha表現、output hash、実行command、exit codeを付ける。参照生成と候補描画の実行状態を別に記録する。
6. 比較結果を`not_implemented / implemented_unverified / pass / fail / unsupported_upstream / blocked_environment`で表す。期待するfixture集合と実行結果集合を照合し、欠落、重複、空集合、追加の未知fixture、旧SHAの結果を受理しない。required fixtureがpassでない場合は最終ゲートを失敗させる。
7. raw bytesの完全一致を初期既定値にする。画素数、最大channel差、平均絶対差、差分bbox、最初の不一致、heatmapも出力する。許容差を導入する際はfixture別manifestに理由・範囲・reviewを保存し、整数領域や画像の欠落を許容しない。
8. 既知差分には理由、最小再現、上流source、担当Issue、対応状態を付ける。上流の制限やpanicはプロセス分離・timeoutで観測する。危険な入力の安全化を上流完全一致のpassへ混ぜず、互換テストと安全性テストを分ける。
9. oracle更新は明示的な変更として行い、旧/新SHAの両参照を候補へ当てる。候補変更と参照画像更新だけで差分を消さない。artifact cacheは全入力hash・toolchain・oracle/candidate SHAをkeyに含める。

## 成果物

- `conformance/rust-oracle/`、fixture schema、fixture manifest、raw/JSON output仕様。
- `conformance/fixtures/`と期待集合、`conformance/results/`のschema。大きな成果物はCI artifactへ保存する。
- ローカル/CI共通の`run_conformance`相当の実行入口と比較器。名称・引数は実装時に確定しREADMEへ記載する。
- 自己検査可能な負の対照群。比較レポートには比較器の自己検査結果も表示する。

## テストと受入条件

1. oracle単体: 同じpin・環境・入力を2回実行しraw hashが再現すること。MoonBit未実装の段階ではoracle成功だけを報告する。
2. 初期fixture: 空/透明背景、1×1、幅1/2/3/4/5/7/8/9、整数矩形、半透明重なり、clip境界、`basic_drawing`を用意する。SIMD幅とtailの差も観測できる寸法にする。
3. 負の対照: 1色変更、1画素変更、alpha変更、fill rule反転、matrix乗算順変更、clip無効化で比較器がFAILになる。対応機能が未実装の対照は未実装として追跡し、全件自己検査済みとしない。
4. fail-closed: oracle/candidate非ゼロ終了、timeout、欠落画像、サイズ/stride違い、hash不一致、古いmanifest、未対応command、空の結果集合、全黒差替えをそれぞれ拒否する。
5. 参照固定の任意fixtureについてRustネイティブ、MoonBit Native、MoonBit JSを比較する。ブラウザの操作表示はRADEN-0009で別途検証する。
6. 上流のx86_64/AArch64で差が出たらarchitecture別に記録し、原因調査なしに共通goldenへ上書きしない。

## 分割と依存

最初のPRはoracleと比較器の自己検査だけで成立させる。次のPRでRADEN-0003の出力を接続する。後続の描画Issueは自分のfixtureをこの基盤へ追加し、全機能完成まで比較を延期しない。

## 対象外

Rust/WASMでのブラウザ内リアルタイムoracle、WebCanvasの描画結果をRust参照として扱うこと、承認なしのgolden自動更新は行わない。

## 根拠

- [上流basic_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [Image raw buffer](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/api/image.rs)
- [JITの整数演算とSIMD/tail](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)

検証状態: 未実行（実装計画）。
