---
id: RADEN-0006
status: open
priority: P2
milestone: M3
depends_on: [RADEN-0005]
---

# stroke-to-fill、cap/join、dashを移植する

## 目的

ストロークを輪郭Pathへ変換して既存fill経路で描く。上流`stroke_drawing`を再現し、線端・接合部・dashを操作できるPlaygroundへつなげる。

## 実装方針

1. 基本はPath平坦化→必要ならdash分割→法線/接合/端処理→輪郭Path→fill_pathの順とする。独立した線描画エンジンを追加してfillとAAの規則を分岐させない。
2. 第1段階はstroke_line/polyline/path、width、Butt/Square/Round cap、Bevel/Round join。第2段階でMiterClip/MiterBevel/MiterRound、miter limit、始端/終端別cap、閉じたshape helperを追加する。
3. stroke widthとmatrixの適用順を固定上流で確認する。非一様scaleやreflectionの時にdevice-space固定幅にするかuser-spaceの輪郭を変換するかを推測しない。描画側の二重変換を防ぐ。
4. dash array/offsetを実装する。上流READMEの奇数長配列を2回繰り返す規則を追跡し、offsetの正/負/周期境界、0長entry、空配列、全長0、不正値を分類する。0長entryで無限ループしない。
5. subpath境界、closed pathの始終点、dashの閉じ目、0長segment、180度反転、非常に鋭い角で輪郭の向きと交点を管理する。分割後のedge/point予算を持たせる。
6. stroke style/alphaとfill style/alphaは独立させる。内部でfill_pathを使ってもContextの既存fill状態を書き換えたままにしない。save/restoreでdash配列やstyleがaliasしないようにする。
7. diagnosticsに中心線、分割後dash、生成輪郭を出せるようにする。最終画像の差がflatten由来かstroke展開由来かを比較器で特定できるようにする。

## 成果物

- stroke-to-fillの純粋関数/workspaceとContext API。
- cap/join/width/miter/dashの対応表と境界fixture。
- `stroke_drawing`の同一sceneを使うNative/JSヘッドレス画像。
- Playgroundでstroke輪郭と元pathを切り替えるための診断情報。

## テストと受入条件

1. cap全種、join全種、miter limit直前/直後、別々の始終cap、開いた線/閉じた輪郭をRustと比較する。
2. 偶数/奇数dash、負offset、周期を跨ぐoffset、短い線、close位置を跨ぐdashでshapeと画素を比較する。
3. 0幅/負幅/非有限幅、重複点、全長0dash、極小segment、極大分割で停止と資源上限を検証する。有効入力互換と不正入力の安全性差分を別に報告する。
4. transform、clip、半透明、global/stroke alpha、save/restoreを組み合わせてもfill状態が変化しないこと。
5. `stroke_drawing`をRADEN-0002に接続し、輪郭/coverage/pixelの比較を保存する。輪郭が一致しない差をrasterizerの許容差へ押し込めない。

## 分割と依存

基本stroke、miter系join、dash、Context/state/diagnosticsの順に分ける。Gradient/Pattern strokeはRADEN-0007のpaint接続後、テキスト輪郭はRADEN-0011で追加する。

## 対象外

完全なSVG stroke仕様、GPU line pipeline、上流未対応の形状効果は含めない。

## 根拠

- [stroke-to-fillの経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [stroke_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/stroke_drawing.rs)
- [cap/join/dash API](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

検証状態: 未実行（実装計画）。
