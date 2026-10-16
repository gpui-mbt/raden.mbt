# stroke-to-fill、cap/join、dashを移植する

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0006-strokes-dashes

Issue: RADEN-0006
Priority: P2
Milestone: M3
Depends-on: RADEN-0005

## 概要

ストロークを輪郭Pathへ変換して既存fill経路で描く。上流 `stroke_drawing` を再現し、線端・接合部・dashを操作できるPlaygroundへつなげる。

## 背景

- 上流のstrokeはstroke-to-fill方式で、独立した線描画エンジンではなくPathの輪郭を生成して既存fill経路へ渡す（[docs/RASTERIZE.md](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)）。
- dash配列の奇数長を2回繰り返す規則など、上流READMEに記載された仕様は固定上流で確認する。
- 本Issueは RADEN-0006（依存: RADEN-0005）。paint接続はRADEN-0007、テキスト輪郭はRADEN-0011。

## 問題

- strokeの展開実装が存在せず、`stroke_drawing` を再現できない。
- cap/join、miter limit、dash分割の規則が未固定だと、輪郭と最終画像の差を切り分けられない。
- dashの不正入力（0長entry、全長0）で無限ループや停止しない可能性がある。

## 目標

- cap/join/width/miter/dashの上流互換の輪郭を生成し、fill_path経由でAA付き描画できる。
- stroke style/alphaがfill状態を破壊せず、save/restoreでdash配列やstyleがaliasしない。
- `stroke_drawing` をRADEN-0002へ接続し、輪郭/coverage/pixelの差を局所化できる。

## 対象外

- 完全なSVG stroke仕様、GPU line pipeline、上流未対応の形状効果。
- gradient/patternによるstroke（RADEN-0007のpaint接続後）。
- テキスト輪郭（RADEN-0011）。

## 提案する方針

1. 基本はPath平坦化→必要ならdash分割→法線/接合/端処理→輪郭Path→fill_pathの順とする。独立した線描画エンジンを追加してfillとAAの規則を分岐させない。
2. 第1段階はstroke_line/polyline/path、width、Butt/Square/Round cap、Bevel/Round join。第2段階でMiterClip/MiterBevel/MiterRound、miter limit、始端/終端別cap、閉じたshape helperを追加する。
3. stroke widthとmatrixの適用順を固定上流で確認する。非一様scaleやreflectionの時にdevice-space固定幅にするかuser-spaceの輪郭を変換するかを推測しない。描画側の二重変換を防ぐ。
4. dash array/offsetを実装する。上流READMEの奇数長配列を2回繰り返す規則を追跡し、offsetの正/負/周期境界、0長entry、空配列、全長0、不正値を分類する。0長entryで無限ループしない。
5. subpath境界、closed pathの始終点、dashの閉じ目、0長segment、180度反転、非常に鋭い角で輪郭の向きと交点を管理する。分割後のedge/point予算を持たせる。
6. stroke style/alphaとfill style/alphaは独立させる。内部でfill_pathを使ってもContextの既存fill状態を書き換えたままにしない。save/restoreでdash配列やstyleがaliasしないようにする。
7. diagnosticsに中心線、分割後dash、生成輪郭を出せるようにする。最終画像の差がflatten由来かstroke展開由来かを比較器で特定できるようにする。

### 成果物

- stroke-to-fillの純粋関数/workspaceとContext API。
- cap/join/width/miter/dashの対応表と境界fixture。
- `stroke_drawing` の同一sceneを使うNative/JSヘッドレス画像。
- Playgroundでstroke輪郭と元pathを切り替えるための診断情報。

### 分割と依存

基本stroke、miter系join、dash、Context/state/diagnosticsの順に分ける。Gradient/Pattern strokeはRADEN-0007のpaint接続後、テキスト輪郭はRADEN-0011で追加する。

## 受け入れ条件

- [ ] Given cap全種、join全種、miter limit直前/直後、別々の始終cap、開いた線/閉じた輪郭, when 描画する, then Rust oracleと比較して期待する輪郭・画素になる。
- [ ] Given 偶数/奇数dash、負offset、周期を跨ぐoffset、短い線、close位置を跨ぐdash, when 描画する, then shapeと画素が上流と一致する。
- [ ] Given 0幅/負幅/非有限幅、重複点、全長0dash、極小segment、極大分割, when 描画する, then 停止と資源上限が機能する。有効入力互換と不正入力の安全性差分を別に報告する。
- [ ] Given transform、clip、半透明、global/stroke alpha、save/restoreの組み合わせ, when 描画する, then fill状態が変化しない。
- [ ] Given `stroke_drawing` とRADEN-0002の比較器, when 輪郭/coverage/pixelを比較する, then 結果が保存され、輪郭不一致をrasterizerの許容差へ押し込めていない。

## テスト計画

- cap/join/miter/dashの境界fixtureをRust oracleと比較する。
- 不正dash入力の停止・エラー確認テストを実行する。
- 状態独立性（fill α、save/restore、style alias）のテストを実行する。
- `stroke_drawing` sceneをNative/JSで生成し、RADEN-0002へ接続する。
- 実行入口はRADEN-0002の `run_conformance` 相当と `moon test` を使う。

## リスク

- stroke widthとmatrix適用順を推測すると、非一様scaleやreflectionで一致しない。固定上流で確認する。
- dashの0長entry・負offsetの処理を誤ると無限ループや不正輪郭になる。分類して上限を設ける。
- 内部でfill_pathを使う際のfill状態汚染は後続描画へ波及する。save/restoreとstate独立性をテストする。
- 輪郭でなくrasterizerの許容差で差を吸収すると、strokeの不具合が隠れる。段階別に比較する。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [stroke-to-fillの経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [stroke_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/stroke_drawing.rs)
- [cap/join/dash API](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM3（描画拡充）に含まれる。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
