# 土台を固定し、何をMoonBitへ移すかを明文化する

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0001-bootstrap-port-contract

Issue: RADEN-0001
Priority: P1
Milestone: M0
Depends-on: なし

## 概要

空の移植先を、上流との差分とtarget別の実行可能性を追跡できるMoonBitプロジェクトにする。Rustの所有権・ポインター・JIT APIをそのまま写すのではなく、描画結果と状態遷移を移植契約にする。

## 背景

- 移植元は `shiguredo/raden` のコミット `afb752e17a69fef8af981251b68de22a7597ff01`（Cargo package `raden` 2026.2.0、Apache-2.0）。上流CargoにはCraneliftの必須依存があるため、Rust版がそのままWASMで動く前提は置かない。
- 移植先の調査基点は `be6ce812cec10c5170b4ec98627cf3c0af0bf124`。現状のリポジトリにはルート `README.md` と実装計画しかなく、MoonBit module、ビルド設定、CI、デモ、上流との比較基盤は存在しない。
- 実装計画は [issues/README.md](../README.md) の12件分割。本Issueは RADEN-0001（依存なし、RADEN-0002以降の土台）。

## 問題

- 固定すべき上流SHA、Rust/Cargo/MoonBit toolchain、確認日が未文書化で、上流`main`やWeb検索のキャッシュを混ぜる余地がある。
- MoonBitへ移す公開APIの範囲と、移さないJIT内部API・可変pixel bufferの所有権境界が未定義。
- target別の実行可能性と、宣言値と実測値の区別が未整理で、未実行のtargetを対応済みに見せてしまう危険がある。

## 目標

- 上流・toolchain・ライセンス・API対応・エラー分類を追跡できる文書群がある。
- Native/JSで同じ純粋計算を実行する最小moduleと、coreだけに依存する独立consumerがある。
- ローカルとCIが同じpinと同じ実行入口を使い、target別の実行結果を未実行と成功に分けて記録できる。

## 対象外

- Rust oracleの本実装（RADEN-0002）とpixel描画（RADEN-0003）。
- toolchainを毎回latestへ更新する運用、全targetへの対応宣言、未測定のゼロコピー化、Windows/Wasm/WasmGCの対応済み宣言。

## 提案する方針

1. 上流SHA `afb752e17a69fef8af981251b68de22a7597ff01` を `upstream.lock.json` へ保存する。repository、Cargo version、Cargo.lock hash、比較用Rustツールチェーン、確認日を含める。Cargoの `rust-version = 1.94` は宣言値であり、ビルド成功の証拠ではない。依存解決を含む `--locked` 実行で使用版を決める。
2. `moon.mod.json` と必要なpackage設定を作る。module名候補は `gpui-mbt/raden` とし、公開名の利用可能性は公開前に確認する。MoonBit compiler、core、依存、Node/ブラウザテスト環境を固定し、`moon version --all` 等の実際の出力を記録する。
3. 初期はNativeとJavaScriptで純粋計算を共有する。nativeの実コンパイラbackend、最適化モード、OS/CPUを記録し、`--target native` だけでC/LLVM等の実体を決めつけない。Wasm/WasmGCは後続でportableなI/O境界を検証するまで実験扱いにする。
4. 公開API対応表 `docs/api-compatibility.md` を作る。上流symbol、上流source、MoonBit API、状態、担当Issue、fixture、意図的差分を1行で追跡する。`src/lib.rs` のre-exportだけでなく、公開module内の利用者向けAPIも棚卸しする。主要描画APIを先行し、低レベルJIT内部APIは非互換と明示する。
5. Image/Contextの所有権を決める。公開APIから無制限に可変pixel bufferを貸し出さない。初期はsnapshot/copyで安全性を優先し、ゼロコピーが必要なら寿命・再確保・複数Contextのaliasingを別途実証する。Rustの `data_ptr_mut` を汎用公開ポインターとして移さない。
6. `PipelineRuntime` をスカラ描画のworkspace/dispatch境界として設計する。JITを持たないことをAPI文書に明記する。単色合成、coverage sweep、edge変換、gradient/pattern fetchを個別に最適化できる責務へ分けるが、未使用の汎用backend frameworkは作らない。
7. `UnsupportedFeature`、`InvalidInput`、`ResourceLimit` 等のエラー分類を設計する。NaN/Infinity、不正dimension、過大path、再帰上限超過を入力時に検出し、途中まで描いた後の失敗で画像をどう扱うかを定義する。外部入力はdraw前に検証し、少なくとも単一commandの失敗がpartial writeにならない方針を採る。
8. Apache-2.0のLICENSEと著作権・改変表示、上流出典を保持する。tigerデータと配布フォントはコードと別に出典・再配布条件を確認する。確認できない資産は公開artifactへ含めず、そのfixtureをblockedとして扱う。

### 成果物

- Native/JSで実行可能な最小moduleと公開APIの独立consumer。
- 上流・toolchain lock、API対応表、既知差分表、ライセンスとアセット台帳。
- ローカルとCIが同じ入口を呼ぶsmokeスクリプト。CLIやコンパイラの架空のオプションは採用しない。
- 画像・パス・フォントの上限を設定し検証する共通ポリシー。予算の初期値は対象デモを測定して決定する。

### 配置案

```text
moon.mod.json
upstream.lock.json
docs/architecture.md
docs/api-compatibility.md
docs/known-differences.md
internal/geometry/   # 座標・行列・Path
internal/pixel/      # packed color・合成
internal/raster/     # edge・coverage
internal/paint/      # gradient・pattern
font/                # 後続の任意package
examples/            # pure scene + target別host
conformance/         # Rust oracle・fixture・result
scripts/             # 再現可能な実行入口
```

これは配置案であり、MoonBitの実際のimport/re-export制約を最小consumerで確認してから確定する。循環依存を避けるため、基礎型からraster/paint、最後にContextへ依存を向ける。公開APIに不要な内部packageを露出しない。

## 受け入れ条件

- [ ] Given 固定上流SHAのcheckout, when `upstream.lock.json` と実際の `--locked` 解決結果を比較する, then repository、Cargo version、Cargo.lock hash、比較用Rustツールチェーン、確認日が一致している。
- [ ] Given 空のリポジトリ, when `moon check --target native`、`moon test --target native`、`moon check --target js`、`moon test --target js` を実行する, then 両targetで最低1件の非空なsmoke testが実行されて通る。テスト0件やcompile-onlyをruntime PASSに数えない。
- [ ] Given core package, when 別consumerから公開APIだけをimportして実行する, then Rust、Cranelift、SDL、gpui、ブラウザDOMのない環境で動く。
- [ ] Given ローカルとCI, when 同じpinと同じ実行入口を使う, then pin不一致が検出される。Mac未実行ならLinux成功と別に記載される。
- [ ] `docs/api-compatibility.md` に主要描画APIが登録され、低レベルJIT内部APIが非互換として明記されている。
- [ ] 既存READMEが保持され、実装済み範囲と実装計画への案内が追加されている。未実装APIに完了マークが付いていない。
- [ ] LICENSEにApache-2.0の表示と上流出典があり、再配布条件を確認できない資産が公開artifactに含まれていない。

## テスト計画

- `moon version --all` を実行し、実際の出力を `upstream.lock.json` のtoolchain記録と比較する。
- `moon check` / `moon test` を `--target native` と `--target js` の両方で実行する。
- 固定checkoutの上流Cargoで `--locked` の依存解決とビルドを行い、解決されたバージョンをlockの記録と比較する。
- 最小consumerをcore packageの外に置き、`moon check` と実行で公開APIだけに依存していることを確認する。
- ローカルsmoke入口とCIが同じスクリプト・同じpinを参照していることを確認する。
- 本Issueの時点では描画結果の比較を行わない（比較はRADEN-0002以降）。

## リスク

- `rust-version = 1.94` は宣言値であり、周辺依存を含めてビルドできる保証はない。乖離した場合は上流SHAの変更ではなく、lock記録の修正と理由追記で対応する。
- module名候補 `gpui-mbt/raden` は公開時に利用できない可能性がある。利用可否は公開前に確認し、公開APIの互換性へ影響する場合は別Issueとして扱う。
- ゼロコピーやJIT互換を先行させると安全性・複雑性のリスクが大きい。初期はcopy/snapshotと明示的な非対応で境界を固定する。
- tiger・フォント等のassetの再配布条件を確認できない場合、該当fixtureはblockedとして進める。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [Cargo](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/Cargo.toml)
- [公開API](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/lib.rs)
- [Imageの所有データ](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/api/image.rs)
- [MoonBit FFI/寿命](https://docs.moonbitlang.com/en/stable/language/ffi.html)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM0（基盤）に含まれ、RADEN-0002以降の前提になる。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
