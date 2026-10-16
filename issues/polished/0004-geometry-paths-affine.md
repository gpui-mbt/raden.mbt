# 幾何・Path・アフィン変換と曲線平坦化を移植する

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0004-geometry-paths-affine

Issue: RADEN-0004
Priority: P1
Milestone: M2
Depends-on: RADEN-0001

## 概要

描画に依存しない幾何コアを作り、上流と同じcommand列・変換順序・線分列を生成する。ラスタライズ後の画像だけでは分かりにくい差を、この段階で局所化する。

## 背景

- 幾何はRADEN-0005のラスタライザとRADEN-0009の操作表示が入力として使う。RADEN-0003と並行して実装できる（[issues/README.md](../README.md) のIssue一覧）。
- 上流docsはde Casteljau分割、flatness tolerance 0.25、最大再帰深さ16を説明しているが、定数・判定式・出力順は実sourceの確認を要する。
- 上流の行列命名（通常transformは後乗算、`post_*` は前乗算）やユーザー座標系の扱いを一般的なCanvas APIの推測で決めない。

## 問題

- Point/Rect/Path/Matrix2D/EdgeBuilderに相当する実装が存在せず、後続Issueの入力形式が未定。
- 行列の乗算順序、flattenのtoleranceと再帰制限、edge出力順、bboxの定義が未固定だと、画像比較でしか差を検出できない。
- 不正なcommand列・特異行列・再帰を使った資源消費の扱いが未定義。

## 目標

- 上流と同じcommand列・変換後point・flatten済みedgeを生成し、JSONで比較できる。
- 有効入力の互換と、不正入力を安全に拒否する差分を分けて記録できる。
- RADEN-0005が使うedge形式と変換済みフラグを合意し、両側で二重変換を起こさない。

## 対象外

- SVG文字列parser、完全なSVG仕様、path boolean演算、厳密bbox、GPU tessellation。
- 描画結果そのもの（RADEN-0005）と操作UI（RADEN-0009）。

## 提案する方針

1. Point、Rect、Line、Circle、Ellipse、RoundRect、Triangle、Arc、Matrix2D、Path/PathCmdを棚卸しする。座標は原則Doubleを使い、後続のgradientにあるFloat相当の丸めと混同しない。shape型を単なる未検証の別名として公開しない。
2. Pathはcommand・point・conic weightの整合を保つ。current point、subpath start、直前command、smooth用control pointを明示して、move/close後の反射点を誤って引き継がない。内部配列の無制限な可変公開で不正command列を作れない設計にする。
3. 第1段階はmove/line/quad/cubic/closeとadd_path/translate/transform。第2段階でsmooth_quad/smooth_cubic/conic/arcとshape helperを追加する。未対応commandはparse時に拒否し、線分への無言の退化でごまかさない。
4. Matrix2Dの積・逆行列・point変換を実装する。通常transformは `matrix = matrix * T`、`post_*` は前乗算という上流の命名規則をそのまま対応表に記録する。rotate_around、skew、user_to_metaの意味を一般的なCanvasの推測で決めず固定上流と照合する。
5. 特異/ほぼ特異行列、NaN/Infinity、巨大座標、負の半径、0長subpathの扱いを分類する。有効入力の互換と、不正入力を安全に拒否する差分を分けてテストする。逆行列失敗をidentityとして成功扱いしない。
6. EdgeBuilder相当を実装する。上流docsはde Casteljau分割、flatness tolerance 0.25、最大再帰深さ16を説明しているため、実sourceの定数・判定式・出力順を確認して合わせる。出力edge数とcommand数に予算を設け、再帰制限だけに資源制限を任せない。
7. **flattenしてからedgeを変換する順序**を初期の上流互換経路とする。device-spaceで先に変換して平坦化する方が都合がよくても、scale依存の曲線分割が変わるため独立した改善として扱う。
8. `control_box` と `bounding_box` は上流の制御点ベースの範囲に合わせ、厳密な曲線extremaを計算するAPIと誤認させない。厳密bboxが必要なら新しい別APIにする。

### 成果物

- geometry/Path/Matrix2DとEdgeBuilderの純粋MoonBit実装。
- command列・変換後point・flatten済みedgeをJSONで比較するtest adapter。
- cubic制御点、平坦化edge、bboxを見せるPlayground用の診断データAPI。描画そのものはRADEN-0005/0009。
- 上流symbolとMoonBit API、座標単位・角度単位・有効入力域の対応表。

### 分割と依存

Point/Matrix/基本Path、shape helper、曲線flatten、拡張commandを別PRにできる。RADEN-0003と並行可能。RADEN-0005に渡すedge形式と変換済みフラグを先に合意し、両側で二重変換しない。

## 受け入れ条件

- [ ] Given translate→rotateとrotate→translate、前乗算と後乗算, when 固定oracleと比較する, then 結果が区別され、identity、reflection、非一様scale、90度回転、中心回転、skewが一致する。
- [ ] Given 複数subpath、close後line、moveのみ、重複点、0長segment、反転path、smoothの直前が別command、conicのweight=1、円弧の0/大きなsweep, when 実行する, then 期待するcommand列とpointになる。
- [ ] Given 小/大scale、尖ったcurve、曲率の強いcubic, when 実行する, then edge数・順序と終点が比較され、max recursion/edge budget到達時の挙動が確認できる。
- [ ] Given 同じcommand・edge fixture, when Native/JSで実行する, then 同じ結果になり、float差が出る場合は当該演算の許容差と根拠を固定し、画像比較の許容差を先に広げない。
- [ ] Given 有限の非特異行列, when inverse round-tripとadd_pathの非破壊性をproperty testで確認する, then 成立する。ただし上流と違う順序の近似をpropertyだけで正しいと判定しない。
- [ ] 未対応commandがparse時に拒否され、線分への無言の退化が起きない。

## テスト計画

- 行列・変換の比較fixture（順序、identity、reflection、scale、回転、skew）を固定oracleと実行する。
- command列とflatten済みedgeのJSON比較adapterをRADEN-0002の比較経路へ接続する。
- Path境界（複数subpath、close、smooth、conic、arc）のfixtureを実行する。
- Native/JSで同じfixtureを実行し、diffを記録する。
- inverse round-tripとadd_path非破壊のproperty testを実行する。

## リスク

- 行列の乗算順序や `post_*` の解釈を誤ると全描画がずれる。上流sourceと対応表で固定する。
- flattenとedge変換の順序を初期に変えると、scale依存の分割が変わって上流一致を失う。初期は上流互換経路を保つ。
- 再帰制限だけに資源制限を任せると、巨大pathで過大なedgeを生成する。edge/command予算を併設する。
- float許容差を画像比較へ先行適用すると、幾何の差が隠れる。幾何段階の差として記録する。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [API対応の起点](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/lib.rs)
- [EdgeBuilder](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/raster/edge_builder.rs)
- [変換とflattenの順序](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [PathとMatrixの対応範囲](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM2（Vector Playground）に含まれ、RADEN-0005とセットで曲線塗りを成立させる。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
