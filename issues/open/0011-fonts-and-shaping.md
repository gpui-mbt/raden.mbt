---
id: RADEN-0011
status: open
priority: P2
milestone: M4
depends_on: [RADEN-0005, RADEN-0006]
---

# TrueTypeアウトラインと限定的なGSUB/GPOSを移植する

## 目的

上流`font_shaping`と同じfont bytes・文字列・feature設定で、glyph列、配置、輪郭、画像を比較できるようにする。OSのtext rendererへ委譲してMoonBitのfont実装完了とはしない。

## 実装方針

1. `font/`を独立packageとし、coreの図形デモには依存させない。FontData.from_bytesを基礎にし、from_fileはNative host、ユーザーによるファイル選択はbrowser hostで実装する。
2. 固定上流が扱うTrueType tableを棚卸しする。head/maxp/hhea/hmtx/cmap/loca/glyf/OS/2、GSUB/GPOSの読み取りはtable境界、offset加算、count×size、indexを検証する。未検証のbuffer sliceや再帰を外部フォントに適用しない。
3. 第1段階はmetadata、cmap、advance、単純glyph outline。第2段階でcompound glyphとmetrics。compoundの再帰深さ、cycle、point数予算を設け、未対応の配置方式を黙って成功にしない。上流のfallbackがあれば既知差分として記録する。
4. 第3段階で上流の限定範囲、GSUB Single/Ligature（Type 1/4）、GPOS Single/Pair（Type 1/2）、liga/kern/cligの切替を移す。lookupの順序、clusterの単位、advance/offsetの座標系をsourceとoracleで固定する。
5. `GlyphBuffer`、glyph id、placement、cluster、TextMetricsを構造化出力する。UTF-8 byte offset、Unicode scalar index、JSのUTF-16 indexを混ぜない。合字によってglyph数が変わってもclusterの意味を保持する。
6. outlineはglyph座標のY-up/baselineから描画座標へ一度だけ変換し、fill_textは上流に合わせたPath合成経路、stroke_textは既存stroke-to-fillへ接続する。font size、feature変更、cloneによるcacheの寿命を定義する。
7. 複雑な日本語組版やRTLが動くと推測しない。扱えるフォント形式/lookup/scriptを対応表へ記載し、上流自身の未対応範囲と移植未実装を区別する。
8. テストfontは出典・ライセンス・hashを固定した再配布可能なものを選ぶ。OSの標準fontや開発者のローカルpathにCIを依存させない。配布可否が未確認ならfontを同梱せず、そのケースをblockedにする。

## 成果物

- FontData/FontFace/Font、glyph buffer/metrics、限定shaping。
- font tableの安全性テストと小さな破損入力corpus。
- `font_shaping` example、feature ON/OFFでのglyph一覧と描画比較。
- font format/lookup/script別の対応表と既知差分。

## テストと受入条件

1. 同じfont hashで`ffi AV fl`等の入力を用い、liga/kern/cligを独立に切り替え、glyph id/cluster/advance/offsetをRustと比較する。画像が近いだけではshaping成功にしない。
2. ASCII、非ASCII、サロゲート対に相当する文字、missing glyph、空文字列、size変更、feature cloneで境界を検証する。一般的な全文字対応の証拠とは扱わない。
3. simple/compound glyph、baseline、Y反転、negative bearing、bounding box、fill/strokeを比較する。構造結果→Path→coverage→pixelの段階で差を局所化する。
4. truncated font、不正table offset/count、glyph cycle、過大点数、無効lookup、未対応formatを安全に拒否する。timeout/ResourceLimitとparse errorを区別する。
5. フォント処理をimportしないcore consumerのsize/依存が増えないこと。Native/JSで同じfont fixtureを使用すること。
6. 再配布条件とsource hashがないfontをpublic artifactへ含めない。未検証fontでのスクリーンショットを標準goldenにしない。

## 分割と依存

parse/metrics、simple outline、compound、GSUB、GPOS、Context/exampleの順に分ける。M1/M2の図形描画やPlayground公開をこのIssueの完了待ちにしない。

## 対象外

CFF/CFF2、可変フォント、Microsoft kern v0、完全なOpenType shaping、bidi/line breaking/fallback、HarfBuzz互換、OS text描画への置換は含めない。

## 根拠

- [固定版のfont対応と制約](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)
- [font_shaping example](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/font_shaping.rs)
- [公開font型](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/lib.rs)

検証状態: 未実行（実装計画）。
