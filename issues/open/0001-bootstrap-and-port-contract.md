---
id: RADEN-0001
status: open
priority: P1
milestone: M0
depends_on: []
---

# 土台を固定し、何をMoonBitへ移すかを明文化する

## 目的

空の移植先を、上流との差分とtarget別の実行可能性を追跡できるMoonBitプロジェクトにする。Rustの所有権・ポインター・JIT APIをそのまま写すのではなく、描画結果と状態遷移を移植契約にする。

## 実装方針

1. 上流SHA`afb752e17a69fef8af981251b68de22a7597ff01`を`upstream.lock.json`へ保存する。repository、Cargo version、Cargo.lock hash、比較用Rustツールチェーン、確認日を含める。Cargoの`rust-version = 1.94`は宣言値であり、ビルド成功の証拠ではない。依存解決を含む`--locked`実行で使用版を決める。
2. `moon.mod.json`と必要なpackage設定を作る。module名候補は`gpui-mbt/raden`とし、公開名の利用可能性は公開前に確認する。MoonBit compiler、core、依存、Node/ブラウザテスト環境を固定し、`moon version --all`等の実際の出力を記録する。
3. 初期はNativeとJavaScriptで純粋計算を共有する。nativeの実コンパイラbackend、最適化モード、OS/CPUを記録し、`--target native`だけでC/LLVM等の実体を決めつけない。Wasm/WasmGCは後続でportableなI/O境界を検証するまで実験扱いにする。
4. 公開API対応表`docs/api-compatibility.md`を作る。上流symbol、上流source、MoonBit API、状態、担当Issue、fixture、意図的差分を1行で追跡する。`src/lib.rs`のre-exportだけでなく、公開module内の利用者向けAPIも棚卸しする。主要描画APIを先行し、低レベルJIT内部APIは非互換と明示する。
5. Image/Contextの所有権を決める。公開APIから無制限に可変pixel bufferを貸し出さない。初期はsnapshot/copyで安全性を優先し、ゼロコピーが必要なら寿命・再確保・複数Contextのaliasingを別途実証する。Rustの`data_ptr_mut`を汎用公開ポインターとして移さない。
6. `PipelineRuntime`をスカラ描画のworkspace/dispatch境界として設計する。JITを持たないことをAPI文書に明記する。単色合成、coverage sweep、edge変換、gradient/pattern fetchを個別に最適化できる責務へ分けるが、未使用の汎用backend frameworkは作らない。
7. `UnsupportedFeature`、`InvalidInput`、`ResourceLimit`等のエラー分類を設計する。NaN/Infinity、不正dimension、過大path、再帰上限超過を入力時に検出し、途中まで描いた後の失敗で画像をどう扱うかを定義する。外部入力はdraw前に検証し、少なくとも単一commandの失敗がpartial writeにならない方針を採る。
8. Apache-2.0のLICENSEと著作権・改変表示、上流出典を保持する。tigerデータと配布フォントはコードと別に出典・再配布条件を確認する。確認できない資産は公開artifactへ含めず、そのfixtureをblockedとして扱う。

## 配置案

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
font/               # 後続の任意package
examples/           # pure scene + target別host
conformance/        # Rust oracle・fixture・result
scripts/            # 再現可能な実行入口
```

これは配置案であり、MoonBitの実際のimport/re-export制約を最小consumerで確認してから確定する。循環依存を避けるため、基礎型からraster/paint、最後にContextへ依存を向ける。公開APIに不要な内部packageを露出しない。

## 成果物

- Native/JSで実行可能な最小moduleと公開APIの独立consumer。
- 上流・toolchain lock、API対応表、既知差分表、ライセンスとアセット台帳。
- ローカルとCIが同じ入口を呼ぶsmokeスクリプト。CLIやコンパイラの架空のオプションは採用しない。
- 画像・パス・フォントの上限を設定し検証する共通ポリシー。予算の初期値は対象デモを測定して決定する。

## テストと受入条件

1. `moon check --target native`、`moon test --target native`、`moon check --target js`、`moon test --target js`を実行し、最低1件の非空のsmoke testを両targetで通す。テスト0件やcompile-onlyをruntime PASSにしない。
2. 別consumerから公開APIをimportし、Rust、Cranelift、SDL、gpui、ブラウザDOMのない環境でcoreを実行する。
3. CIとローカルが同じpinを使い、pin不一致を検出する。Mac未実行ならLinux成功と分けて記載する。
4. 既存READMEを保持し、実装済み範囲とこの計画への案内を追加する。未実装APIに完了マークを付けない。

## 対象外

Rust oracleの本実装はRADEN-0002、pixel描画はRADEN-0003。ツールチェーンを毎回latestに更新する運用、全targetへの対応宣言、未測定のゼロコピー化は行わない。

## 根拠

- [Cargo](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/Cargo.toml)
- [公開API](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/lib.rs)
- [Imageの所有データ](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/api/image.rs)
- [MoonBit FFI/寿命](https://docs.moonbitlang.com/en/stable/language/ffi.html)

検証状態: 未実行（実装計画）。
