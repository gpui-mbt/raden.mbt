# Gradient・Pattern・Blitと合成モードを拡充する

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0007-gradients-patterns-blit

Issue: RADEN-0007
Priority: P2
Milestone: M3
Depends-on: RADEN-0005

## 概要

同じcoverage生成に複数のpaint sourceを接続し、`gradient_drawing` と `blit_clip_pattern_paths` を再現する。上流の高速経路ごとの制約を把握してから、改善と互換を分けて実装する。

## 背景

- 上流はpaintをSolid/Gradient/Patternに分け、固定小数点のLUT/incrementと高速経路を持つ。JITと数値近似の詳細は [docs/JIT.md](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md) が説明する。
- 上流固定READMEには、gradientのfill_rectでcomp opが無視される経路、patternのfill_rectでSrcCopy/SrcOver以外がpanicとなる経路の記述がある。READMEだけで全経路に同じ制限があると決めつけない。
- 本Issueは RADEN-0007（依存: RADEN-0005）。strokeへのpaint適用はRADEN-0006実装後。

## 問題

- paint sourceが単色のみで、gradient/pattern/blitを描けない。
- paintの変換順序、extend、filter、cacheの無効化条件が未定義。
- CompOpが初期4種のみで、上流29種の対応関係が未追跡。

## 目標

- Linear/Radial/Conic gradient、Pattern（Nearest/Bilinear）、blit、29種のCompOpがoperation×paint×formatの対応表とともに追跡される。
- `gradient_drawing` と `blit_clip_pattern_paths` をRADEN-0002へ接続し、異なるstop/filter/comp opの負の対照が失敗する。
- mutableなstyle/imageを更新した時に古いcacheを返さない。

## 対象外

- HDR/広色域、色管理の全面実装、高次補間、画像codec一式、GPU texture。
- 上流制限の無条件な修正（改善は既知差分として記録する）。

## 提案する方針

1. paintをSolid/Gradient/Patternに分け、prepare→span fetch→coverage→blendという責務にする。変換やLUT構築は可能な限りdrawの外側へ出すが、mutableなstyle/imageを更新した時のcache invalidationを定義する。最初は安全なsnapshotを優先する。
2. Linear gradientを先行する。stop順序、同一offset、端点、空/1 stop、Pad/Repeat/Reflect、premultiplied LUT、固定小数点incrementとroundingを上流source/oracleで確認する。単に端点間のDouble補間に置き換えない。
3. 次にRadialとConicを追加する。Radialの焦点/半径/退化ケース、Conicの角度wrap、境界、上流f32の演算・atan2近似を追跡する。一般のsqrt/atan2へ置き換えて画素差を一律許容するのではなく、同じアルゴリズムを移すか差分APIにするか明示する。
4. Patternにorigin/transform、Pad/Repeat/Reflect、Nearest/Bilinearを実装する。device→texture変換の合成順を固定し、負座標のmodulo、境界、半画素位置、透明texelをテストする。gradientとpatternの既定extendが同じだと仮定しない。
5. blit_image_at/rectは上流対応のNearest、source/destination rect、clip、SrcCopy/SrcOverから始める。source format、dest format、alpha、global alpha、matrix適用をoperation別に観測する。同じImage内の重なり転送は一時snapshotまたは安全な非対応エラーとし、順序依存の破損を防ぐ。
6. RADEN-0003に残したCompOpを拡充する。Porter-Duff群、Plus/Minus/Modulate、Multiply以降のblend群をsub-PRに分け、上流29種を個別に追跡する。単色/可変span、完全/部分coverage、formatの組み合わせを明示し、enumだけ追加して対応済みにしない。
7. fill/stroke paint、global alpha、fill/stroke alpha、clip、transform、save/restoreを接続する。stroke paintの最終受入はRADEN-0006実装後に行う。
8. 固定上流READMEが説明する、gradient fill_rectでcomp opが無視される経路、pattern fill_rectでSrcCopy/SrcOver以外がpanicとなる経路を最小fixtureで観測する。identity/nonidentity、alpha=1/1未満、fill_rect/fill_pathを分ける。
9. 安全なMoonBit errorを返す場合と、上流制約を改善して任意CompOpを適用する場合は既知差分へ記録する。見た目を改善した結果を固定上流との完全互換PASSへ混ぜない。

### 成果物

- Gradient/Pattern/Blit/CompOpの実装とoperation×paint×format対応表。
- 5種類の配置を持つ `gradient_drawing` scene、`blit_clip_pattern_paths` scene。
- stop、extend、filter、matrix、opacity、comp opを切り替えるPlayground用model。
- cache寿命、source image mutation、snapshot/copyの契約とテスト。

### 分割と依存

合成モード追加、Linear、Radial/Conic、Pattern、Blit、Context統合とexampleの順に分割できる。各段階の公開対応表を更新し、一つの巨大PRにしない。

## 受け入れ条件

- [ ] Given gradient各種の端点/継ぎ目、Repeat/Reflectの負/正周期、透明stop、duplicate stop、特異matrix、退化gradient, when 描画する, then 上流と一致する。
- [ ] Given patternの1×1/非正方画像、負origin、非一様scale、rotation、Nearest/Bilinearと透明境界, when 描画する, then 上流と一致する。
- [ ] Given blitの全外/部分clip、source crop、拡大/縮小、半透明、重なりsource、未対応format/operation, when 実行する, then 期待する結果または明示的なエラーになる。
- [ ] Given CompOp全29種, when 対応表を埋め、alpha=0/1/127/128/254/255とcoverage境界を含む小画像で比較する, then 個別に追跡される。blendの色空間を独自にlinear-lightへ変更しない。
- [ ] Given fast pathとfallback, when 両方を実際に通す, then 上流自身に差のあるケースが明示される。候補だけ常にfallbackへ逃がしてAPI条件を未検証にしない。
- [ ] Given Native/JS、保存/復元、描画後のsource/style変更, when 描画する, then 一致し、cacheが古いLUT/画像を返す不具合が検出される。
- [ ] Given 両exampleとRADEN-0002, when 異なるstop/filter/comp opを投入した負の対照を実行する, then FAILになる。

## テスト計画

- gradient/pattern/blitの境界fixtureをRust oracleと比較する。
- CompOp対応表を埋め、小画像の組み合わせテストを実行する。
- fast path/fallbackの両経路を通すテストを実行する。
- cache invalidationとsource mutationのテストを実行する。
- 両exampleをNative/JSで生成し、RADEN-0002へ接続する。

## リスク

- 一般的なsqrt/atan2やDouble補間へ置き換えると、画素差が恒常化する。上流アルゴリズムを確認して一致させるか、差分APIとして明示する。
- 上流のpanic・制限を安全なエラーへ置き換えると、完全互換PASSと矛盾する。既知差分として分離して記録する。
- cacheを持つとmutation後に古い結果を返す危険がある。invalidation契約とテストを先に定義する。
- 同時に全paintを実装すると対応表が埋まらないまま巨大PRになる。段階分割と公開対応表の更新を維持する。

## 変更履歴

`CHANGES.md` impact: no

## 根拠

- [paint/gradientの処理経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [JITと数値近似](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)
- [gradient_drawing](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/gradient_drawing.rs)
- [blit_clip_pattern_paths](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/examples/blit_clip_pattern_paths.rs)
- [固定版の制約](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/README.md)

## 注記

- 検証状態: 未実行（実装計画）。
- 本Issueは [issues/README.md](../README.md) のM3（描画拡充）に含まれる。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
