# 解析的ラスタライズとcoverageを移植する

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0005-analytic-rasterizer

Issue: RADEN-0005
Priority: P1
Milestone: M2
Depends-on: RADEN-0003, RADEN-0004

## 概要

任意Pathから上流と同じcoverageを生成し、アンチエイリアス付き塗りつぶしを行う。別方式のsupersamplingで似た絵を出すのではなく、上流のedge/cell/sweep経路を移す。

## 背景

- 上流の解析的ラスタライザはedge走査、固定小数点cellのarea/cover、scanline sweep、NonZero/EvenOddの規則を組み合わせる。丸め・右shift・overflowの扱いが言語間で偶然一致することは期待できない（[docs/RASTERIZE.md](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)）。
- 入力のedge形式はRADEN-0004と合意し、二重変換を避ける。出力のspanはRADEN-0003の合成とRADEN-0007のpaintが受け取る。
- 本Issueは RADEN-0005（依存: RADEN-0003、RADEN-0004）。

## 問題

- ラスタライザが存在せず、Pathを入力にしたAA付き塗りつぶしができない。
- coverage、cell、scanline境界、fill ruleの規則が未固定だと、画像差の原因を幾何・raster・合成のどこにも局所化できない。
- workspaceの再利用時に前フレームの状態を持ち越す危険がある。

## 目標

- NonZero/EvenOddの塗りが上流と同じcoverageで生成され、`fill_path` から `fill_rect` のpath fallbackまで接続される。
- edge/cell/coverage/画素のどこで差が始まったかを診断出力で示せる。
- 同じImage/Runtimeの反復利用、サイズ変更、空pathの後でも単独描画と同じ出力になる。

## 対象外

- パスclip、MSAA/GPU、タイル並列化、SIMD/JIT生成。
- 矩形clipは既存Contextの責務とする。
- gradient/patternのpaint接続（RADEN-0007）とstroke展開（RADEN-0006）。

## 提案する方針

1. `src/raster/analytic.rs` のedge走査、固定小数点への変換、cellのarea/cover packing、scanline境界、clip、整数幅・符号を棚卸しする。丸め・右shift・overflowの扱いは言語間で偶然同じになることを期待しない。
2. edgeをY下限で処理し、scanlineごとにarea-coverを蓄積する。画像外のedgeも内外判定に影響するため、左端より外にあるedgeを単純に捨ててwindingを失わない。上流のclip処理と有効な入力域を比較する。
3. JIT sweepをMoonBitのスカラ関数へ移す。prefix sum、算術右shift9、NonZeroの絶対値/clamp、EvenOddの周期折り返しを個別にテストする。NonZero/EvenOddの違いをfill stageで後から近似しない。
4. 出力は `y / x_start / coverage bytes` のspanとして、単色合成、後続gradient/patternへ渡す。0/255 coverageとpartial coverageを区別し、span終端・空span・clip境界を明示する。coverage scratch bufferを跨いで保持させる場合はcopy/寿命契約を定める。
5. `Context.fill_path` に接続し、fill_circle/ellipse/round_rect/triangle/polygon/pieをPath経由で実装する。非identityなfill_rectは上流同様のpath fallbackへつなげる。matrixやalphaをfast pathとfallbackで二重適用しない。
6. raster workspaceは行/画像の反復実行で再利用するが、初期化漏れで前フレームのcell/coverageを持ち越さない。画像サイズ変更、描画なし、clip空の早期return経路でも状態を正しく戻す。
7. 最大edge、cell、scanline幅、累積coverの安全範囲を入力予算と結び付ける。Int64等へ広げると上流overflow結果と違う場合は安全性差分として記録し、通常有効入力の画素一致と区別する。

### 成果物

- スカラAnalyticRasterizer、NonZero/EvenOdd sweep、span受け渡し。
- edge、cell、coverage、最終pixelのどこで差が始まったか示す診断出力。
- 自己交差、穴、複数subpath、curve、回転形状のfixture群。
- Playgroundのcoverage/edge表示に必要な読み取り専用診断データ。

### 分割と依存

cell/sweep単体、polygon fill、curve/shape接続、workspace/bounds強化の順に分ける。最適化は正しいスカラ経路を残したままRADEN-0012で実施する。

## 受け入れ条件

- [ ] Given 手計算できる小さな水平/垂直edge、三角形、矩形、小数位置の境界, when cellとcoverageを比較する, then 期待値に一致する。画像比較だけで符号の不具合を見逃さない。
- [ ] Given 同心shapeの穴、向きの異なるsubpath、自己交差、接するedge、重なるedge、clipを跨ぐ巨大shape, when NonZero/EvenOddで実行する, then Rust oracleと一致する。
- [ ] Given 全透明/全不透明/半透明の色とcoverageの組み合わせ, when 描画する, then coverageの二重乗算・alphaの二重premultiplyが起きない。
- [ ] Given 同じImage/Runtimeの繰り返し使用, when サイズ変更、clear、空pathの後で再描画する, then 単独描画と同じ出力になり、複数Context間でscratch stateが漏れない。
- [ ] Given `fill_rect` のidentity fast pathとpath経路が等価になる入力, when 照合する, then 一致する。小数座標等で上流自身に経路差がある場合は同値を強制せず既知差分を残す。
- [ ] Given float/curve誤差, when 差を調査する, then flatten/edge/cellへ遡って説明できる。整数coverageは完全一致を原則とし、未知の差をAA差として自動許容しない。
- [ ] Given RADEN-0002の負の対照（fill rule、clip、1画素）, when 実行する, then FAILになる。

## テスト計画

- 手計算fixture（水平/垂直edge、三角形、矩形、小数境界）でcellとcoverageを検証する。
- NonZero/EvenOddの形状fixture群をRust oracleと比較する。
- 色×coverageの組み合わせテストを実行する。
- workspace再利用とサイズ変更の反復テストを実行する。
- `fill_rect` fast pathとpath経路の照合テストを実行する。
- RADEN-0002の負の対照と接続して実行する。

## リスク

- 丸め・右shift・overflowの差異が画像差として現れ、原因が特定しにくい。edge/cell/coverage段階の診断を先行して用意する。
- 画像外edgeの扱いを単純化するとwindingが変わる。内外判定への影響を確認する。
- workspace再利用時の初期化漏れはフレーム間で再現しない不具合になる。独立した状態検証テストを持つ。
- 上流overflowと異なる安全化は意図的差分として記録し、通常有効入力の一致と混ぜない。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [AnalyticRasterizer](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/raster/analytic.rs)
- [描画経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [sweepの演算](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM2（Vector Playground）に含まれ、曲線・穴・clip操作の基盤になる。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
