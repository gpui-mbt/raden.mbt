---
id: RADEN-0005
status: open
priority: P1
milestone: M2
depends_on: [RADEN-0003, RADEN-0004]
---

# 解析的ラスタライズとcoverageを移植する

## 目的

任意Pathから上流と同じcoverageを生成し、アンチエイリアス付き塗りつぶしを行う。別方式のsupersamplingで似た絵を出すのではなく、上流のedge/cell/sweep経路を移す。

## 実装方針

1. `src/raster/analytic.rs`のedge走査、固定小数点への変換、cellのarea/cover packing、scanline境界、clip、整数幅・符号を棚卸しする。丸め・右shift・overflowの扱いは言語間で偶然同じになることを期待しない。
2. edgeをY下限で処理し、scanlineごとにarea-coverを蓄積する。画像外のedgeも内外判定に影響するため、左端より外にあるedgeを単純に捨ててwindingを失わない。上流のclip処理と有効な入力域を比較する。
3. JIT sweepをMoonBitのスカラ関数へ移す。prefix sum、算術右shift9、NonZeroの絶対値/clamp、EvenOddの周期折り返しを個別にテストする。NonZero/EvenOddの違いをfill stageで後から近似しない。
4. 出力は`y / x_start / coverage bytes`のspanとして、単色合成、後続gradient/patternへ渡す。0/255 coverageとpartial coverageを区別し、span終端・空span・clip境界を明示する。coverage scratch bufferを跨いで保持させる場合はcopy/寿命契約を定める。
5. `Context.fill_path`に接続し、fill_circle/ellipse/round_rect/triangle/polygon/pieをPath経由で実装する。非identityなfill_rectは上流同様のpath fallbackへつなげる。matrixやalphaをfast pathとfallbackで二重適用しない。
6. raster workspaceは行/画像の反復実行で再利用するが、初期化漏れで前フレームのcell/coverageを持ち越さない。画像サイズ変更、描画なし、clip空の早期return経路でも状態を正しく戻す。
7. 最大edge、cell、scanline幅、累積coverの安全範囲を入力予算と結び付ける。Int64等へ広げると上流overflow結果と違う場合は安全性差分として記録し、通常有効入力の画素一致と区別する。

## 成果物

- スカラAnalyticRasterizer、NonZero/EvenOdd sweep、span受け渡し。
- edge、cell、coverage、最終pixelのどこで差が始まったか示す診断出力。
- 自己交差、穴、複数subpath、curve、回転形状のfixture群。
- Playgroundのcoverage/edge表示に必要な読み取り専用診断データ。

## テストと受入条件

1. 手計算できる小さな水平/垂直edge、三角形、矩形、小数位置の境界でcellとcoverageを検証する。画像比較だけで符号の不具合を見逃さない。
2. 同心shapeの穴、向きの異なるsubpath、自己交差、接するedge、重なるedge、clipを跨ぐ巨大shapeでNonZero/EvenOddをRust oracleと比較する。
3. 全透明/全不透明/半透明の色とcoverageを組み合わせ、coverageの二重乗算・alphaの二重premultiplyがないことを確認する。
4. 同じImage/Runtimeを繰り返し使用し、サイズ変更、clear、空pathの後でも単独描画と同じ出力になること。複数Context間でscratch stateが漏れないこと。
5. `fill_rect`のidentity fast pathとpath経路を、等価になる入力で照合する。小数座標等で上流自身に経路差がある場合は同値を強制せず既知差分を残す。
6. float/curve誤差はまずflatten/edge/cellへ遡って説明する。整数coverageは完全一致を原則とし、未知の差をAA差として自動許容しない。
7. RADEN-0002のfill-rule/clip/1画素の負の対照がFAILになることを確認する。

## 分割と依存

cell/sweep単体、polygon fill、curve/shape接続、workspace/bounds強化の順に分ける。最適化は正しいスカラ経路を残したままRADEN-0012で実施する。

## 対象外

パスclip、MSAA/GPU、タイル並列化、SIMD/JIT生成は初期に含めない。矩形clipは既存Contextの責務とする。

## 根拠

- [AnalyticRasterizer](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/raster/analytic.rs)
- [描画経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [sweepの演算](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)

検証状態: 未実行（実装計画）。
