---
id: RADEN-0007
status: open
priority: P2
milestone: M3
depends_on: [RADEN-0005]
---

# Gradient・Pattern・Blitと合成モードを拡充する

## 目的

同じcoverage生成に複数のpaint sourceを接続し、`gradient_drawing`と`blit_clip_pattern_paths`を再現する。上流の高速経路ごとの制約を把握してから、改善と互換を分けて実装する。

## 実装方針

1. paintをSolid/Gradient/Patternに分け、prepare→span fetch→coverage→blendという責務にする。変換やLUT構築は可能な限りdrawの外側へ出すが、mutableなstyle/imageを更新した時のcache invalidationを定義する。最初は安全なsnapshotを優先する。
2. Linear gradientを先行する。stop順序、同一offset、端点、空/1 stop、Pad/Repeat/Reflect、premultiplied LUT、固定小数点incrementとroundingを上流source/oracleで確認する。単に端点間のDouble補間に置き換えない。
3. 次にRadialとConicを追加する。Radialの焦点/半径/退化ケース、Conicの角度wrap、境界、上流f32の演算・atan2近似を追跡する。一般のsqrt/atan2へ置き換えて画素差を一律許容するのではなく、同じアルゴリズムを移すか差分APIにするか明示する。
4. Patternにorigin/transform、Pad/Repeat/Reflect、Nearest/Bilinearを実装する。device→texture変換の合成順を固定し、負座標のmodulo、境界、半画素位置、透明texelをテストする。gradientとpatternの既定extendが同じだと仮定しない。
5. blit_image_at/rectは上流対応のNearest、source/destination rect、clip、SrcCopy/SrcOverから始める。source format、dest format、alpha、global alpha、matrix適用をoperation別に観測する。同じImage内の重なり転送は一時snapshotまたは安全な非対応エラーとし、順序依存の破損を防ぐ。
6. RADEN-0003に残したCompOpを拡充する。Porter-Duff群、Plus/Minus/Modulate、Multiply以降のblend群をsub-PRに分け、上流29種を個別に追跡する。単色/可変span、完全/部分coverage、formatの組み合わせを明示し、enumだけ追加して対応済みにしない。
7. fill/stroke paint、global alpha、fill/stroke alpha、clip、transform、save/restoreを接続する。stroke paintの最終受入はRADEN-0006実装後に行う。
8. 固定上流READMEが説明する、gradient fill_rectでcomp opが無視される経路、pattern fill_rectでSrcCopy/SrcOver以外がpanicとなる経路を最小fixtureで観測する。identity/nonidentity、alpha=1/1未満、fill_rect/fill_pathを分ける。READMEだけで全経路に同じ制限があると決めつけない。
9. 安全なMoonBit errorを返す場合と、上流制約を改善して任意CompOpを適用する場合は既知差分へ記録する。見た目を改善した結果を固定上流との完全互換PASSへ混ぜない。

## 成果物

- Gradient/Pattern/Blit/CompOpの実装とoperation×paint×format対応表。
- 5種類の配置を持つ`gradient_drawing` scene、`blit_clip_pattern_paths` scene。
- stop、extend、filter、matrix、opacity、comp opを切り替えるPlayground用model。
- cache寿命、source image mutation、snapshot/copyの契約とテスト。

## テストと受入条件

1. gradient各種の端点/継ぎ目、Repeat/Reflectの負/正周期、透明stop、duplicate stop、特異matrix、退化gradientを比較する。
2. patternの1×1/非正方画像、負origin、非一様scale、rotation、Nearest/Bilinearと透明境界を比較する。
3. blitの全外/部分clip、source crop、拡大/縮小、半透明、重なりsource、未対応format/operationのエラーを検証する。
4. CompOp全29種の対応表を埋め、実装対象ごとにalpha=0/1/127/128/254/255とcoverage境界を含む小画像で比較する。blendの色空間を独自にlinear-lightへ変更しない。
5. fast pathとfallbackの両方を実際に通し、上流自身に差のあるケースを明示する。候補だけ常にfallbackへ逃がしてAPI条件を未検証にしない。
6. Native/JS、保存/復元、描画後のsource/style変更で比較する。cacheが古いLUT/画像を返す不具合を検出する。
7. 両exampleをRADEN-0002へ接続し、異なるstop/filter/comp opを投入した負の対照が失敗すること。

## 分割と依存

合成モード追加、Linear、Radial/Conic、Pattern、Blit、Context統合とexampleの順に分割できる。各段階の公開対応表を更新し、一つの巨大PRにしない。

## 対象外

HDR/広色域、色管理の全面実装、高次補間、画像codec一式、GPU texture、上流制限の無条件な修正は含めない。

## 根拠

- [paint/gradientの処理経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [JITと数値近似](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)
- [gradient_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/gradient_drawing.rs)
- [blit_clip_pattern_paths](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/blit_clip_pattern_paths.rs)
- [固定版の制約](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

検証状態: 未実行（実装計画）。
