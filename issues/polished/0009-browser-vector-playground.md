# MoonBitライブ描画とRust参照を並べるVector Playground

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0009-browser-playground

Issue: RADEN-0009
Priority: P1
Milestone: M1-M3
Depends-on: RADEN-0002, RADEN-0008

## 概要

最初はbasic_drawingをブラウザで表示し、次に曲線・paint・strokeを操作できる比較デモへ育てる。描画コアはMoonBit、DOM/UI/ピクセル表示は薄いJS hostとする。

## 背景

- ブラウザではRustのライブ実行を前提にせず、固定Rust参照画像とMoonBitのライブ描画を比較する。参照画像であることの明示は [issues/README.md](../README.md) の設計判断3に従う。
- MoonBit JS出力のexport関数、typed array、buffer ownershipを固定toolchainで実証する必要がある。Canvasのpath/gradient APIに描画計算を委譲しない。
- 本Issueは RADEN-0009（依存: RADEN-0002、RADEN-0008）。M1はbasic presetの表示と操作だけで足りる。

## 問題

- ブラウザでMoonBit描画を実行・表示する手段がなく、利用者が成果を確認できない。
- 参照画像とライブ描画の区別、未比較状態の表示、古い非同期結果の破棄が未設計。
- CSS表示サイズと描画pixelサイズの変換を誤ると、pointer操作と比較結果がずれる。

## 目標

- basic presetをブラウザで表示し、入力hash・参照SHA・判定を常時確認できる。
- M2/M3でpath制御点、fill rule、matrix、clip、coverage/edge overlay、stroke、gradient、pattern、comp opを操作できる。
- 参照欠落・未比較・失敗をPASSと区別して表示し、古いrequest結果を採用しない。

## 対象外

- Rust/WASMの強制移植、任意Rustをブラウザで実行するサーバー、Canvasへの描画委譲、全SVGエディター、最初からのWorker pool。
- deployそのもの（ローカルbuildとE2E完了後の明示的な判断で行う）。

## 提案する方針

1. `examples/browser/` にES moduleとしてMoonBit JS出力を組み込む。export関数、typed array、buffer ownershipを固定toolchainで実証し、生成JSの内部symbolを直参照しない。ビルドにNodeを使う場合でも、閲覧時はstatic hostingのみで動く構成にする。
2. UIは「Rust native reference」「MoonBit live」「差分/診断」を並べる。Rust側はRADEN-0002が生成した固定画像であり、WASMによるライブRust実行ではないと常時表示する。source/candidate SHA、fixture hash、寸法、target、判定、実行時刻/生成条件を見える位置に置く。
3. M1はbasic_drawing preset、リセット、再描画、画像download、zoom、背景checkerだけでよい。M2でpath制御点、fill rule、matrix、clip、coverage/edge overlayを追加し、M3でstroke width/cap/join/dash、gradient stop、pattern filter、comp opを追加する。
4. 生bufferから表示用RGBAへ変換する。BGRA/ARGBの並びとpremultiplied→straightの変換を独立関数にし、alpha=0/1/128/255で検証する。Canvasのpath/gradient APIに描画計算を委譲せず、ピクセル転送だけを行う。
5. 比較は表示canvasの再読出しではなくcanonical raw bytesで行う。CanvasやPNGのalpha丸め・色処理を描画コア差として数えない。画像表示の正しさは別のスクリーンショット/E2Eとして検証する。
6. preset変更後は同じ入力hashのRust referenceだけを採用する。制御点等を任意編集した場合、対応する参照がなければ「参照なし/未比較」と表示する。元presetの画像をそのまま使って不一致率を出さない。静的サイトで任意入力のRust参照を自動生成できるように見せない。
7. request id、input hash、candidate versionを描画request/resultへ持たせ、古い非同期結果を破棄する。初期は同期描画＋入力debounceでもよいが、重いsceneでUIが止まる場合はWorkerへ分離し、cancel/terminateと再生成をテストする。
8. importするfixture JSONはschema検証し、command/edge/image予算を適用する。任意コード、eval、任意shell、credentialを扱わない。font/画像URL等を無制限に取得する機能は初期に含めない。
9. CSS表示sizeと描画pixel size、devicePixelRatioを分離する。pointerからscene座標への変換は縮尺・scroll・CSS sizeを含めて計算する。1280×720等の実寸をmanifestから読み、500×500などの固定前提を比較器へ埋め込まない。
10. deployはローカルbuildとE2Eの完了後に行う。GitHub Pages等の公開先、base path、権限、既存サイトの有無を確認する。計画追加をデプロイ許可・公開完了とは扱わない。

### 成果物

- basicと段階別に機能が増えるVector Playground。
- URL/query等で復元できるschema化されたpreset state、reset、固定frame操作。
- raw比較と表示E2Eを分離したテスト、参照画像manifest、static build。
- 未実装/未比較/参照生成失敗をそのまま表示するstatus UI。

## 受け入れ条件

- [ ] Given 実ブラウザ, when MoonBitの描画を実行する, then 既定presetのraw hashがheadless JS/Nativeと一致する。画像ファイルを左右に貼るだけで完成にしない。
- [ ] Given pointer drag、数値入力、reset、preset切替、freeze/step, when 実際のDOMイベントで操作する, then 入力hashと描画結果の対応が確認できる。無効な機能は無言で反応しない。
- [ ] Given 参照欠落、画像寸法不一致、旧SHAのmanifest、候補描画の例外、連続requestの順序逆転, when 注入する, then 以前のPASSが残らない。
- [ ] Given DPR=1/2、viewport変更、scroll、resize, when 操作する, then 座標変換と表示が検証される。GPU/Canvas表示だけPASSでもcoreの画素一致は別欄に残す。
- [ ] Given 明示的に色/alpha/clipを壊した候補, when 表示する, then FAIL表示になる。未比較はFAILともPASSとも別に表示される。
- [ ] Given static build, when ローカルHTTPで開く, then subpath配信、reload、asset path、初回アクセスで動く。外部サービス停止が基本presetを壊さない。
- [ ] 参照画像がRustのライブ実行ではないこと、各表示のSHA/hash/判定がUI上で確認できる。

## テスト計画

- 実ブラウザでbasic presetを描画し、headless JS/Nativeとのraw hash比較を実行する。
- DOMイベントによる操作テスト（drag、入力、reset、切り替え、freeze/step）を実行する。
- 故障注入（参照欠落、寸法不一致、旧manifest、例外、順序逆転）のテストを実行する。
- DPR/viewport/scroll/resizeの座標変換テストを実行する。
- static buildをローカルHTTPで配信してE2Eを実行する。

## リスク

- 参照画像をライブRust結果と誤認させると、比較の意味が崩れる。UI上で常時明示する。
- 古い非同期結果や元presetの画像を採用すると、偽のPASS/FAILになる。request idと入力hashで破棄する。
- Canvasのalpha丸めや色処理をコア差として数えると、誤った差分になる。canonical raw bytesで比較する。
- 外部サービスや巨大assetへの依存は初期プリセットを壊す。静的hostのみで完結させる。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [上流の依存構造](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/Cargo.toml)
- [上流pixel表示の境界](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [MoonBit JS/FFI](https://docs.moonbitlang.com/en/stable/language/ffi.html)

## 注記

- 検証状態: M1 完了 (2026-10-17 再検証)。chromium headless E2E 30/30、
  node 純粋ロジック 15/15、native 75 / js 58 tests、conformance 95/95。
  受け入れ条件のうち M1 の表示・操作・故障注入は検証済み。M2/M3 の編集 UI
  (制御点・stroke・gradient 操作) は未実装で、release manifest でも
  not_implemented と明示する。deploy は未実施 (ローカル検証のみ)。
- 本Issueは [issues/README.md](../README.md) のM1〜M3（最初のデモ〜Vector Playground）にまたがる。deployと公開は本Issueの実装完了後の別判断。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
