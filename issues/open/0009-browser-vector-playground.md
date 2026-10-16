---
id: RADEN-0009
status: open
priority: P1
milestone: M1-M3
depends_on: [RADEN-0002, RADEN-0008]
---

# MoonBitライブ描画とRust参照を並べるVector Playground

## 目的

最初はbasic_drawingをブラウザで表示し、次に曲線・paint・strokeを操作できる比較デモへ育てる。描画コアはMoonBit、DOM/UI/ピクセル表示は薄いJS hostとする。

## 実装方針

1. `examples/browser/`にES moduleとしてMoonBit JS出力を組み込む。export関数、typed array、buffer ownershipを固定toolchainで実証し、生成JSの内部symbolを直参照しない。ビルドにNodeを使う場合でも、閲覧時はstatic hostingのみで動く構成にする。
2. UIは「Rust native reference」「MoonBit live」「差分/診断」を並べる。Rust側はRADEN-0002が生成した固定画像であり、WASMによるライブRust実行ではないと常時表示する。source/candidate SHA、fixture hash、寸法、target、判定、実行時刻/生成条件を見える位置に置く。
3. M1はbasic_drawing preset、リセット、再描画、画像download、zoom、背景checkerだけでよい。M2でpath制御点、fill rule、matrix、clip、coverage/edge overlayを追加し、M3でstroke width/cap/join/dash、gradient stop、pattern filter、comp opを追加する。
4. 生bufferから表示用RGBAへ変換する。BGRA/ARGBの並びとpremultiplied→straightの変換を独立関数にし、alpha=0/1/128/255で検証する。Canvasのpath/gradient APIに描画計算を委譲せず、ピクセル転送だけを行う。
5. 比較は表示canvasの再読出しではなくcanonical raw bytesで行う。CanvasやPNGのalpha丸め・色処理を描画コア差として数えない。画像表示の正しさは別のスクリーンショット/E2Eとして検証する。
6. preset変更後は同じ入力hashのRust referenceだけを採用する。制御点等を任意編集した場合、対応する参照がなければ「参照なし/未比較」と表示する。元presetの画像をそのまま使って不一致率を出さない。静的サイトで任意入力のRust参照を自動生成できるように見せない。
7. request id、input hash、candidate versionを描画request/resultへ持たせ、古い非同期結果を破棄する。初期は同期描画＋入力debounceでもよいが、重いsceneでUIが止まる場合はWorkerへ分離し、cancel/terminateと再生成をテストする。
8. importするfixture JSONはschema検証し、command/edge/image予算を適用する。任意コード、eval、任意shell、credentialを扱わない。font/画像URL等を無制限に取得する機能は初期に含めない。
9. CSS表示sizeと描画pixel size、devicePixelRatioを分離する。pointerからscene座標への変換は縮尺・scroll・CSS sizeを含めて計算する。1280×720等の実寸をmanifestから読み、500×500などの固定前提を比較器へ埋め込まない。
10. deployはローカルbuildとE2Eの完了後に行う。GitHub Pages等の公開先、base path、権限、既存サイトの有無を確認する。今回の計画追加をデプロイ許可・公開完了とは扱わない。

## 成果物

- basicと段階別に機能が増えるVector Playground。
- URL/query等で復元できるschema化されたpreset state、reset、固定frame操作。
- raw比較と表示E2Eを分離したテスト、参照画像manifest、static build。
- 未実装/未比較/参照生成失敗をそのまま表示するstatus UI。

## テストと受入条件

1. 実ブラウザでMoonBitの描画を実行し、既定presetのraw hashをheadless JS/Nativeと比較する。画像ファイルを左右に貼るだけで完成にしない。
2. pointer drag、数値入力、reset、preset切替、freeze/stepを実際のDOMイベントで操作し、入力hashと描画結果の対応を確かめる。無効な機能は無言で反応しないUIにしない。
3. 参照欠落、画像寸法不一致、旧SHAのmanifest、候補描画の例外、連続requestの順序逆転を注入し、以前のPASSが残らないこと。
4. DPR=1/2、viewport変更、scroll、resize後の座標変換と表示を検証する。GPU/Canvas表示だけPASSでもcoreの画素一致は別欄に残す。
5. 明示的に色/alpha/clipを壊した候補でFAIL表示になること。未比較はFAILともPASSとも別に表示する。
6. static buildをローカルHTTPで開き、subpath配信、reload、asset path、初回アクセスで動くこと。外部サービス停止が基本presetを壊さないこと。

## 対象外

Rust/WASMの強制移植、任意Rustをブラウザで実行するサーバー、Canvasへの描画委譲、全SVGエディター、最初からのWorker poolは含めない。

## 根拠

- [上流の依存構造](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/Cargo.toml)
- [上流pixel表示の境界](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [MoonBit JS/FFI](https://docs.moonbitlang.com/en/stable/language/ffi.html)

検証状態: 未実行（実装計画）。
