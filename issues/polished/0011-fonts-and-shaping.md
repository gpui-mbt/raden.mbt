# TrueTypeアウトラインと限定的なGSUB/GPOSを移植する

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0011-fonts-shaping

Issue: RADEN-0011
Priority: P2
Milestone: M4
Depends-on: RADEN-0005, RADEN-0006

## 概要

上流 `font_shaping` と同じfont bytes・文字列・feature設定で、glyph列、配置、輪郭、画像を比較できるようにする。OSのtext rendererへ委譲してMoonBitのfont実装完了とはしない。

## 背景

- 上流が扱うTrueType tableとshapingの範囲は限定的で、CFF/CFF2、可変フォント、完全なOpenType shapingは対象外（[issues/README.md](../README.md) の初期スコープ外）。
- outlineはglyph座標から描画座標へ一度だけ変換し、既存のfill/stroke-to-fill経路へ接続する。RADEN-0005/0006が前提。
- 本Issueは RADEN-0011（依存: RADEN-0005、RADEN-0006）。

## 問題

- FontData/FontFace/Font、glyph buffer、shapingの実装が存在せず、`font_shaping` を再現できない。
- table境界・offset・countを検証しないparserを外部フォントへ適用すると、危険な読み取りや過大確保につながる。
- 再配布可能なテストfontが未選定で、CIがOS fontやローカルpathに依存する危険がある。

## 目標

- 固定font hashでglyph id/cluster/advance/offsetがRust oracleと一致し、outlineのfill/strokeが画像まで一致する。
- truncated font、不正table offset、glyph cycle等を安全に拒否し、timeout/ResourceLimitとparse errorを区別する。
- font packageをimportしないcore consumerの依存とsizeが増えない。

## 対象外

- CFF/CFF2、可変フォント、Microsoft kern v0、完全なOpenType shaping、bidi/line breaking/fallback、HarfBuzz互換、OS text描画への置換。

## 提案する方針

1. `font/` を独立packageとし、coreの図形デモには依存させない。FontData.from_bytesを基礎にし、from_fileはNative host、ユーザーによるファイル選択はbrowser hostで実装する。
2. 固定上流が扱うTrueType tableを棚卸しする。head/maxp/hhea/hmtx/cmap/loca/glyf/OS/2、GSUB/GPOSの読み取りはtable境界、offset加算、count×size、indexを検証する。未検証のbuffer sliceや再帰を外部フォントに適用しない。
3. 第1段階はmetadata、cmap、advance、単純glyph outline。第2段階でcompound glyphとmetrics。compoundの再帰深さ、cycle、point数予算を設け、未対応の配置方式を黙って成功にしない。上流のfallbackがあれば既知差分として記録する。
4. 第3段階で上流の限定範囲、GSUB Single/Ligature（Type 1/4）、GPOS Single/Pair（Type 1/2）、liga/kern/cligの切替を移す。lookupの順序、clusterの単位、advance/offsetの座標系をsourceとoracleで固定する。
5. `GlyphBuffer`、glyph id、placement、cluster、TextMetricsを構造化出力する。UTF-8 byte offset、Unicode scalar index、JSのUTF-16 indexを混ぜない。合字によってglyph数が変わってもclusterの意味を保持する。
6. outlineはglyph座標のY-up/baselineから描画座標へ一度だけ変換し、fill_textは上流に合わせたPath合成経路、stroke_textは既存stroke-to-fillへ接続する。font size、feature変更、cloneによるcacheの寿命を定義する。
7. 複雑な日本語組版やRTLが動くと推測しない。扱えるフォント形式/lookup/scriptを対応表へ記載し、上流自身の未対応範囲と移植未実装を区別する。
8. テストfontは出典・ライセンス・hashを固定した再配布可能なものを選ぶ。OSの標準fontや開発者のローカルpathにCIを依存させない。配布可否が未確認ならfontを同梱せず、そのケースをblockedにする。

### 成果物

- FontData/FontFace/Font、glyph buffer/metrics、限定shaping。
- font tableの安全性テストと小さな破損入力corpus。
- `font_shaping` example、feature ON/OFFでのglyph一覧と描画比較。
- font format/lookup/script別の対応表と既知差分。

### 分割と依存

parse/metrics、simple outline、compound、GSUB、GPOS、Context/exampleの順に分ける。M1/M2の図形描画やPlayground公開をこのIssueの完了待ちにしない。

## 受け入れ条件

- [ ] Given 同じfont hashと `ffi AV fl` 等の入力, when liga/kern/cligを独立に切り替えてRustと比較する, then glyph id/cluster/advance/offsetが一致する。画像が近いだけではshaping成功にしない。
- [ ] Given ASCII、非ASCII、サロゲート対に相当する文字、missing glyph、空文字列、size変更、feature clone, when 実行する, then 境界が検証される。一般的な全文字対応の証拠とは扱わない。
- [ ] Given simple/compound glyph、baseline、Y反転、negative bearing、bounding box、fill/stroke, when 比較する, then 構造結果→Path→coverage→pixelの段階で差が局所化される。
- [ ] Given truncated font、不正table offset/count、glyph cycle、過大点数、無効lookup、未対応format, when 読み込む, then 安全に拒否され、timeout/ResourceLimitとparse errorが区別される。
- [ ] Given core consumer, when 依存とsizeを検査する, then font処理をimportしていない。Native/JSで同じfont fixtureを使用する。
- [ ] 再配布条件とsource hashがないfontがpublic artifactへ含まれず、未検証fontのスクリーンショットが標準goldenになっていない。

## テスト計画

- 固定font hashでliga/kern/clig切替のglyph結果をRust oracleと比較する。
- 破損font corpusと資源上限のテストを実行する。
- outlineからpixelまでの段階比較テストを実行する。
- Native/JSで同じfont fixtureを実行する。
- `font_shaping` exampleをRADEN-0002へ接続して実行する。

## リスク

- 外部フォントのtableを検証せず読むと、危険な読み取りや暴走につながる。境界・count・再帰・点数を検証する。
- インデックス単位（UTF-8 byte、scalar、UTF-16）を混ぜるとcluster対応が壊れる。単位を固定して構造化出力する。
- 全文字・複雑組版が動くと推測すると対応範囲を過大表示する。対応表と上流未対応範囲を明記する。
- テストfontの再配布条件が未確認だと配布できない。hashと出典を固定し、未確認はblockedにする。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [固定版のfont対応と制約](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)
- [font_shaping example](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/font_shaping.rs)
- [公開font型](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/lib.rs)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM4（Native統合・テキスト）に含まれ、gpui統合（RADEN-0010）とは別々に判定する。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
