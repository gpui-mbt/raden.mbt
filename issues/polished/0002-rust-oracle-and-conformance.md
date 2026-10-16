# 固定Rust oracleと、誤って成功しない比較基盤を作る

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0002-rust-oracle-conformance

Issue: RADEN-0002
Priority: P1
Milestone: M0
Depends-on: RADEN-0001

## 概要

見た目の模倣ではなく、同じ入力に対するRust版とMoonBit版の描画結果・状態・エラーを比較する基盤を作る。描画実装に先行して固定Rust oracleと比較器を作り、MoonBit実装の到着後にfixtureを順次有効化する。

## 背景

- 比較元は実際のRustネイティブ実行とする。上流CargoのCranelift必須依存のため、Rust版がそのままWASMで動く前提は置かず、ブラウザでは固定Rust参照画像とMoonBitのライブ描画を比較する（参照画像であることはRADEN-0009で明示する）。
- 共通合格基準（[issues/README.md](../README.md)）は、成果物への入力hash・上流SHA・candidate SHA・target・ツールチェーンの埋め込み、statusの区別、生ピクセル完全一致、負の対照の検証を要求する。
- 本Issueは RADEN-0002（依存: RADEN-0001）。MoonBit側の描画実装はRADEN-0003以降が担当する。

## 問題

- 現状は比較基盤がなく、MoonBit実装の正しさを上流の観測結果と照合できない。
- 上流の図形描画を別言語で再実装したものをoracleと称すると、偽陽性・偽陰性を検出できない。
- fixture/resultの形式、status語彙、artifactの同一性条件が未定義で、古い画像・欠落・空集合で緑になり得る。

## 目標

- 固定SHAのRustネイティブ実行から、raw pixel bufferとJSON metadataを再現可能に生成できる。
- 入力hash・toolchain・oracle/candidate SHAを埋め込んだ比較結果を、欠落・重複・旧SHAを受理しないfail-closedなゲートとして集約できる。
- 比較器自身が負の対照（1色/1画素/alpha/fill rule/matrix順/clip変更）でFAILになることを自己検査できる。

## 対象外

- Rust/WASMでのブラウザ内リアルタイムoracle。
- WebCanvasの描画結果をRust参照として扱うこと。
- 承認なしのgolden自動更新。
- MoonBit側の描画実装（RADEN-0003以降）。

## 提案する方針

1. `conformance/rust-oracle/` を独立したRust CLIにする。`raden` はGit dependencyの `rev` または固定checkoutのpath dependencyでSHAを固定し、Cargo.lockを保存する。製品libraryやMoonBit consumerには依存させない。上流本体はread-onlyとする。
2. oracleは上流APIを実際に呼び、windowなしでraw pixel bufferとJSON metadataを出力する。`basic_drawing` の描画命令は同じ座標・順序・色で移し、SDL/raw_player表示はoracleへ持ち込まない。上流の図形描画を別言語で再実装してoracleと称さない。
3. 入力schema v1を定義する。`fixture_id / width / height / pixel_format / commands / seed / frame_index / fps / input_hash` を含め、数値型、有限値、単位、command順序を固定する。hash対象は正規化したpayloadとしhash自身を含めない。未知commandや未知enumはエラーにする。
4. 出力はcanonicalなチャンネル順のpremultiplied raw bytesとする。BGRA→RGBA等の並び替えは明記し、unpremultiplyや色空間変換をコア比較へ混ぜない。PNG/BMPは閲覧用で、ファイル圧縮差を不一致判定に使わない。
5. metadataにupstream SHA、oracle adapter SHA、candidate SHA、fixture/input hash、toolchain、target、OS/arch、寸法、stride、alpha表現、output hash、実行command、exit codeを付ける。参照生成と候補描画の実行状態を別に記録する。
6. 比較結果を `not_implemented / implemented_unverified / pass / fail / unsupported_upstream / blocked_environment` で表す。期待するfixture集合と実行結果集合を照合し、欠落、重複、空集合、追加の未知fixture、旧SHAの結果を受理しない。required fixtureがpassでない場合は最終ゲートを失敗させる。
7. raw bytesの完全一致を初期既定値にする。画素数、最大channel差、平均絶対差、差分bbox、最初の不一致、heatmapも出力する。許容差を導入する際はfixture別manifestに理由・範囲・reviewを保存し、整数領域や画像の欠落を許容しない。
8. 既知差分には理由、最小再現、上流source、担当Issue、対応状態を付ける。上流の制限やpanicはプロセス分離・timeoutで観測する。危険な入力の安全化を上流完全一致のpassへ混ぜず、互換テストと安全性テストを分ける。
9. oracle更新は明示的な変更として行い、旧/新SHAの両参照を候補へ当てる。候補変更と参照画像更新だけで差分を消さない。artifact cacheは全入力hash・toolchain・oracle/candidate SHAをkeyに含める。

### 成果物

- `conformance/rust-oracle/`、fixture schema、fixture manifest、raw/JSON output仕様。
- `conformance/fixtures/` と期待集合、`conformance/results/` のschema。大きな成果物はCI artifactへ保存する。
- ローカル/CI共通の `run_conformance` 相当の実行入口と比較器。名称・引数は実装時に確定しREADMEへ記載する。
- 自己検査可能な負の対照群。比較レポートには比較器の自己検査結果も表示する。

### 分割と依存

最初のPRはoracleと比較器の自己検査だけで成立させる。次のPRでRADEN-0003の出力を接続する。後続の描画Issueは自分のfixtureをこの基盤へ追加し、全機能完成まで比較を延期しない。

## 受け入れ条件

- [ ] Given 同じpin・環境・入力, when oracleを2回実行する, then raw hashが再現し、MoonBit未実装の段階ではoracle成功だけが報告される。
- [ ] Given 初期fixture（空/透明背景、1×1、幅1/2/3/4/5/7/8/9、整数矩形、半透明重なり、clip境界、`basic_drawing`）, when oracleと比較器へ通す, then 期待集合と実行結果集合が一致して照合される。
- [ ] Given 負の対照（1色変更、1画素変更、alpha変更、fill rule反転、matrix乗算順変更、clip無効化）, when 比較器へ通す, then FAILになる。未実装機能の対照は未実装として追跡し、全件自己検査済みとしない。
- [ ] Given oracle/candidateの非ゼロ終了、timeout、欠落画像、サイズ/stride違い、hash不一致、古いmanifest、未対応command、空の結果集合、全黒差替え, when 比較器へ通す, then それぞれ拒否される。
- [ ] Given 参照固定の任意fixture, when Rustネイティブ、MoonBit Native、MoonBit JSを比較する, then 結果が記録される。ブラウザの操作表示はRADEN-0009で別途検証する。
- [ ] 上流のx86_64/AArch64で差が出た場合、architecture別に記録され、原因調査なしに共通goldenへ上書きされない。
- [ ] 全artifactに上流入力hash・toolchain・oracle/candidate SHAが埋め込まれ、どれかが欠けた結果は未検証として扱われる。

## テスト計画

- oracleの二重実行によるraw hash再現を確認する。
- 初期fixture群をRustネイティブで生成し、期待集合・重複・欠落の照合ロジックを実行する。
- 負の対照群を実行し、FAIL検出とレポート表示を確認する。
- fail-closed注入（非ゼロ終了、timeout、欠落、サイズ違い、旧manifest等）を実行する。
- 実行コマンドはREADMEへ記載し、実装時に正確な名称へ更新する。

## リスク

- 比較器や許容差の運用が甘くなると、見た目の近似や古い参照で緑になる。完全一致とfail-closedを初期既定値として維持する。
- 上流のpanic・過大確保など危険な挙動は再現必須にしない。安全なエラーとの意図的差分を記録し、互換テストと混ぜない。
- 上流CargoはCranelift依存があり、oracleのビルドとSHA固定に手間がかかる。lockと固定checkoutで再現性を確保する。
- Web検索や上流`main`のキャッシュを混ぜると参照がずれる。同じSHAのREADME・source・Cargo.lockだけを根拠にする。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [上流basic_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [Image raw buffer](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/api/image.rs)
- [JITの整数演算とSIMD/tail](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM0（基盤）に含まれ、RADEN-0003以降の描画Issueがfixtureを追加する土台になる。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
