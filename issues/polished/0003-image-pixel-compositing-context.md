# Image・ピクセル合成・Contextで最初の画像を描く

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0003-image-compositing

Issue: RADEN-0003
Priority: P1
Milestone: M1
Depends-on: RADEN-0001

## 概要

`basic_drawing` をMoonBitだけで描ける最小コアを作る。曲線、JIT、ウィンドウ、フォントを必要としない縦切りで、NativeとJSの両方から同じピクセルを得る。

## 背景

- 最初の縦切りは「Prgb32画像 → SrcCopy/SrcOverの矩形 → 上流basic_drawingと同じ1280×720画像 → Rust oracleとの画素比較 → ブラウザ表示」とする（[issues/README.md](../README.md) の設計判断1）。本IssueはこのうちMoonBit側の描画コアを担当する。
- 比較基盤はRADEN-0002、上流exampleの実行と表示はRADEN-0008/0009が担当する。本Issueは RADEN-0003（依存: RADEN-0001）。
- 上流の整数合成とJIT SIMD/tailの演算は、一般的な浮動小数点の合成式へ置き換えると一致しない箇所がある。

## 問題

- Image/Rgba32/Context/合成の実装が存在せず、後続のラスタライザやpaintが依存する土台がない。
- byte order、stride、premultiply、alpha=0のRGB、丸めとclamp、clipとsave/restoreの状態規則が未定義。
- 未対応formatや非identity変換を無言のno-opにすると、M1の画素比較が偽陽性になる。

## 目標

- Prgb32画像と整数矩形の `SrcCopy / SrcOver / Clear / Plus` が、上流 `basic_drawing` の1280×720画像と生ピクセルで一致する。
- Native/JSで同じraw bytesが得られ、RADEN-0002の比較器に接続できる。
- clip・save/restore・alphaの状態が、後から変更しても保存済み状態を変えない値として管理される。

## 対象外

- 29モード全部の合成モードはRADEN-0007。
- pathと変換の実描画はRADEN-0004/0005。
- BMPとウィンドウ表示はRADEN-0008以降。
- 未対応formatのfallbackを使って成功扱いすること。

## 提案する方針

1. `Image` にwidth/height/stride/formatと所有bufferを持たせる。初期formatはPrgb32。packed pixelは論理ARGB、外部byte orderは明示的に固定し、ホストのendian任せで変換しない。上流basic_drawingのLE BGRAをcanonical形式へ変換する規則をRADEN-0002と共有する。
2. `width * bytes_per_pixel`、`stride * height` はoverflowと上限を確保前に検証する。0寸法の扱い、padding付きstride、buffer length不一致を仕様化する。初期constructorが連続bufferのみを許す場合でも、将来host adapterが勝手に同じ前提へ依存しないようstrideをAPIに残す。
3. `Rgba32` 入力、premultiply、unpremultiplyの役割を分ける。描画内部はpremultipliedで統一し、unpremultiplyは表示/exportの必要な場所だけで行う。alpha=0のRGB、rounding、clamp、符号付きshift、packed UInt操作を明示する。
4. `SrcCopy`、`SrcOver`、`Clear`、`Plus` のスカラ演算を小さな関数で実装する。上流JITの `(x * 257 + 257) >> 16` 等の整数処理と実際のsourceを確認し、一般的な浮動小数点の合成式へ置き換えない。完全coverageと部分coverageの経路を分けてテストする。
5. `Context` にfill/stroke styleの土台、comp op、global/fill/stroke alpha、matrix、rect clip、save stackを持たせる。初期styleは単色。save/restoreは値として状態を保持し、後からstyle/clipを変更して保存状態まで変わらないようにする。stack空のrestoreの挙動は上流観測と安全方針を記録する。
6. `fill_all`、identity変換の `fill_rect`、`clear_all`、`clear_rect`、`clip_to_rect`、`restore_clipping` を実装する。clipは画像境界との積集合を維持する。clearはfill style/comp opに依存しない操作として調べ、`clear_rect` の座標系を通常fillと混同しない。
7. M1では整数座標の矩形を完全対応とし、小数矩形の端点処理も上流で調べて対応表へ分ける。未実装の非identity変換や未知formatを無言のno-opにしない。RADEN-0005でpath fallbackを接続するまでは明示的な未対応結果にする。
8. Xrgb32/A8は次のsub-PRで追加する。上流固定READMEのA8対応範囲は限定的であるため、Prgb32に名前だけ付け替えない。format×operationの対応表とテストを作り、alphaの意味とX channelの出力を観測する。

### 成果物

- 公開Image/Rgba32/Context API、スカラ合成、bounds/clip/state実装。
- 純粋な `basic_drawing` scene。1280×720、背景と3矩形の値・順序を上流と一致させる。
- raw buffer出力APIとNative/JS consumer。ファイルI/Oはここへ入れずRADEN-0008のhostへ渡す。
- API対応表に「Prgb32整数矩形」「小数矩形」「Xrgb32」「A8」を別行で記載する。

## 受け入れ条件

- [ ] Given alpha/coverageの0、1、127、128、254、255と端点、完全透明、完全不透明、半透明の連続重ね描き, when 上流と比較する, then 整数合成が生ピクセルで完全一致する（M1のゲート）。
- [ ] Given 矩形が全外、各辺を横断、負座標、0サイズ、1画素、clip空、clip復元、save/restore入れ子, when 描画する, then 期待する結果になり、画像外のguard領域が変わらない。
- [ ] Given 幅1/2/3/4/5/7/8/9, when Native/JSで同じsceneを実行する, then 同じraw bytesになる。
- [ ] Given 過大dimension、不正stride、非有限alpha/座標、上限超過, when 描画する, then 予測可能なエラーになり、途中の画像破壊や過大確保が起きない。
- [ ] Given RADEN-0002の比較器, when `basic_drawing` 全画素の一致と、色/alpha/clipの負の対照を実行する, then 検出結果が期待どおりになる。単体テストだけではM1完了としない。
- [ ] 未実装のformat・変換に対する結果が黙った成功やno-opではなく、明示的な未対応として記録される。

## テスト計画

- `basic_drawing` の1280×720画像をNative/JSで生成し、RADEN-0002のoracleと生ピクセル完全一致を確認する。
- alpha/coverage端点と矩形境界の単体テストを実行する。
- 幅1..9のraw bytesをNative/JSで比較する。
- エラー導入（過大dimension、不正stride、非有限値）の単体テストを実行する。
- 実行入口は `moon test --target native`、`moon test --target js` とRADEN-0002で確定する `run_conformance` 相当を使う。

## リスク

- byte orderやpacked pixelの規則をホスト任せにすると環境差で不一致になる。論理ARGBと外部byte orderを明示して共有する。
- stride/overflow検証を怠ると過大確保やbuffer破壊につながる。確保前に検証する。
- 上流がpanic・過大確保となる入力は安全なエラーへ置き換える。互換テストと安全性テストを分けて記録する。
- Xrgb32/A8をPrgb32の名前替えとして実装するとalphaの意味が崩れる。format×operationの対応表で分離する。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [Image](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/api/image.rs)
- [basic_drawingの寸法・色・byte order](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/basic_drawing.rs)
- [整数合成](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)
- [固定版の対応範囲](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM1（最初のデモ）に含まれる。M0のoracle単体経路ではまだMoonBit互換と称さない。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
