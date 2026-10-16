---
id: RADEN-0004
status: open
priority: P1
milestone: M2
depends_on: [RADEN-0001]
---

# 幾何・Path・アフィン変換と曲線平坦化を移植する

## 目的

描画に依存しない幾何コアを作り、上流と同じcommand列・変換順序・線分列を生成する。ラスタライズ後の画像だけでは分かりにくい差を、この段階で局所化する。

## 実装方針

1. Point、Rect、Line、Circle、Ellipse、RoundRect、Triangle、Arc、Matrix2D、Path/PathCmdを棚卸しする。座標は原則Doubleを使い、後続のgradientにあるFloat相当の丸めと混同しない。shape型を単なる未検証の別名として公開しない。
2. Pathはcommand・point・conic weightの整合を保つ。current point、subpath start、直前command、smooth用control pointを明示して、move/close後の反射点を誤って引き継がない。内部配列の無制限な可変公開で不正command列を作れない設計にする。
3. 第1段階はmove/line/quad/cubic/closeとadd_path/translate/transform。第2段階でsmooth_quad/smooth_cubic/conic/arcとshape helperを追加する。未対応commandはparse時に拒否し、線分への無言の退化でごまかさない。
4. Matrix2Dの積・逆行列・point変換を実装する。通常transformは`matrix = matrix * T`、`post_*`は前乗算という上流の命名規則をそのまま対応表に記録する。rotate_around、skew、user_to_metaの意味を一般的なCanvasの推測で決めず固定上流と照合する。
5. 特異/ほぼ特異行列、NaN/Infinity、巨大座標、負の半径、0長subpathの扱いを分類する。有効入力の互換と、不正入力を安全に拒否する差分を分けてテストする。逆行列失敗をidentityとして成功扱いしない。
6. EdgeBuilder相当を実装する。上流docsはde Casteljau分割、flatness tolerance 0.25、最大再帰深さ16を説明しているため、実sourceの定数・判定式・出力順を確認して合わせる。出力edge数とcommand数に予算を設け、再帰制限だけに資源制限を任せない。
7. **flattenしてからedgeを変換する順序**を初期の上流互換経路とする。device-spaceで先に変換して平坦化する方が都合がよくても、scale依存の曲線分割が変わるため独立した改善として扱う。
8. `control_box`と`bounding_box`は上流の制御点ベースの範囲に合わせ、厳密な曲線extremaを計算するAPIと誤認させない。厳密bboxが必要なら新しい別APIにする。

## 成果物

- geometry/Path/Matrix2DとEdgeBuilderの純粋MoonBit実装。
- command列・変換後point・flatten済みedgeをJSONで比較するtest adapter。
- cubic制御点、平坦化edge、bboxを見せるPlayground用の診断データAPI。描画そのものはRADEN-0005/0009。
- 上流symbolとMoonBit API、座標単位・角度単位・有効入力域の対応表。

## テストと受入条件

1. translate→rotateとrotate→translate、前乗算と後乗算で結果を区別する。identity、reflection、非一様scale、90度回転、中心回転、skewを固定oracleと比較する。
2. 複数subpath、close後line、moveのみ、重複点、0長segment、反転path、smoothの直前が別command、conicのweight=1、円弧の0/大きなsweepを検証する。
3. 小/大scale、尖ったcurve、曲率の強いcubicでedge数・順序と終点を比較する。max recursion/edge budget到達時の挙動を確かめる。
4. Native/JSで同じcommand・edge fixtureを実行する。float差が出る場合は当該演算の許容差と根拠を固定し、画像比較の許容差を先に広げない。
5. 有限の非特異行列に対するinverse round-tripや、add_pathが入力Pathを破壊しないことをproperty testで確認する。ただし上流と違う順序の近似をpropertyだけで正しいと判定しない。

## 分割と依存

Point/Matrix/基本Path、shape helper、曲線flatten、拡張commandを別PRにできる。RADEN-0003と並行可能。RADEN-0005に渡すedge形式と変換済みフラグを先に合意し、両側で二重変換しない。

## 対象外

SVG文字列parser、完全なSVG仕様、path boolean演算、厳密bbox、GPU tessellationは含めない。

## 根拠

- [API対応の起点](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/lib.rs)
- [EdgeBuilder](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/raster/edge_builder.rs)
- [変換とflattenの順序](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [PathとMatrixの対応範囲](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

検証状態: 未実行（実装計画）。
