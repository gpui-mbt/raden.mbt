# 回帰ゲート・性能測定・preview配布を整える

Status: polished
Model: deepseek-v4.1-flash-free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/RADEN-0012-quality-performance-release

Issue: RADEN-0012
Priority: P2
Milestone: M5
Depends-on: RADEN-0002, RADEN-0008

## 概要

描画結果が合うスカラ実装を基準に、品質と性能を測定できる状態へ進める。未対応の範囲を隠さず、宣言した範囲を独立consumerが利用できるpreviewとして配布する。

## 背景

- 回帰ゲートはM0/M1から小さく追加し、M5でまとめて作らない（[issues/README.md](../README.md) の共通合格基準とM5）。
- 性能目標は移植版のbaseline計測後に固定する。上流の1080p/120fpsという目的を達成済み数値として転用しない。
- 本Issueは RADEN-0012（依存: RADEN-0002、RADEN-0008）。previewは全12Issueの完了を必須にしない。

## 問題

- 現状はCI、回帰ゲート、性能測定、配布手順がなく、変更の正しさと退行を継続的に確認できない。
- ベンチ成功を正しさの代用にすると、画素が変わった最適化を採用してしまう。
- 未対応機能・targetを隠した配布や、未測定の速度保証は信頼を損なう。

## 目標

- 必須jobの結果集合をfail-closedで集約し、skip/cancel/missingを成功としない回帰ゲートがある。
- 同じfixture/seed/frame/sizeでRust nativeとMoonBit Nativeを比較したperformance reportがある。
- release manifestで宣言した範囲だけを、独立consumerが利用できるpreviewとして配布できる。publish/deployは明示的な実行判断を経る。

## 対象外

- 未測定の速度保証、上流への無断push、全target一括公開、スコアだけでの品質評価、デモ表示のfpsとCPU描画速度の混同。
- 未検証機能・targetのpreview対応宣言。

## 提案する方針

1. RADEN-0001の基本CIを拡張する。format/API整合、Native/JS単体テスト、Rust oracle比較、比較器の負の対照、example smoke、browser E2Eを別jobとして扱う。全jobの結果集合を集約し、required jobがskip/cancel/missingの場合も成功としない。
2. ローカル用scriptをCIから呼び、GitHub Actions内だけに判定ロジックを書かない。既存運用に合わせactrunによる実行入口も検討し、runnerがなくても個別scriptは直接実行可能にする。
3. gpui Native実機、Mac、追加Wasm targetは実行環境ごとのgateへ分ける。環境不足はblocked/未実行として表示し、headless成功をGUI成功へ集計しない。previewに含める機能・targetはrelease manifestで明示する。
4. turtlesはpixel rounding、clip、matrix order、fill rule、dash境界、font bounds、manifest照合を優先して使う。mutationのsurvivorを分類し、equivalentでないsurvivorはfixtureを追加する。mutation scoreだけを目標にしない。
5. hotpathはflatten、stroke expansion、raster cell/sweep、solid blend、gradient/pattern fetch、buffer allocation/copyを計測する。turtles/hotpath/vlmkitは開発用とし、libraryやデモのruntime依存へ入れない。各toolの実際の公開version/APIを導入時に確認する。
6. benchmarkは同一fixture/seed/frame/sizeを使い、Rust nativeとMoonBit Nativeを同一machine/設定で比較する。MoonBit JSは別系列にする。cold start、Rust JIT compile、warm render、pixel conversion、upload/presentを分離し、p50/p95、frame数、variance、peak memory、出力hashを保存する。
7. 最初に測定するsceneはbasic、curve/polygon、stroke、Linear/Radial/Conic、pattern、tigerまたは権利確認済みの複雑scene、animationとする。小画像、1280×720、1920×1080を使い、固定frame数runと時間制限runを区別する。
8. 最適化順は不要allocation/copy削減、workspace再利用、bounds/empty-spanの早期除外、LUT/cache、単色/不透明fast path、専用dispatchとする。画素hashと境界testを各変更で再確認し、スカラ参照経路を削除しない。
9. SIMD/JIT/C FFIは実測で大きな価値があり、target・安全性・配布制約を満たす場合だけ別設計を起こす。CraneliftをFFIで呼ぶ案は「純MoonBitコア＋任意Native accelerator」として明示し、最初の移植完了条件にしない。
10. 性能予算はbaseline計測後に固定する。shared CIでの一律fps gateを初日から置かず、noiseを記録した上で専用runnerの相対退行gateを検討する。上流の1080p/120fpsという目的を移植版の達成済み数値へ転用しない。
11. 配布は実装範囲、API、依存、license、toolchain、既知差分、target別結果を揃えてから行う。Mooncakes library、必要ならJS wrapper/型定義、CLI binaryとmoon-binstall metadata、GitHub Releaseを別成果物として扱う。package名とversionを確認し、latestだけに依存しない。
12. previewは全12Issueの完了を必須にしない。release manifestで宣言した範囲に限り合格を要求し、font/Native GUI等の未対応をREADME/デモへ明示する。ただしCIと独立consumer未検証の機能をpreview対応に入れない。publish/deployは明示的な実行判断を経る。

### 成果物

- 共通test/benchmark script、CI matrix、fail-closedな集約結果。
- 正常/不正入力corpus、負の対照、mutationの評価記録。
- 固定入力と実行条件を持つperformance reportと改善前後の画素比較。
- release manifest、公開API/対応表、独立consumer、SBOMまたは依存/asset台帳、release手順。

## 受け入れ条件

- [ ] Given 空のconsumer, when 公開libraryを導入してNative/JSでbasic_drawingを実行する, then リポジトリ内の非公開helperや未公開ローカル依存なしで動く。
- [ ] Given fault injection（candidate fail、oracle fail、job cancel、結果欠落、古いSHA、意図的な1画素差）, when release gateを実行する, then すべて拒否される。
- [ ] Given 最適化前後, when required fixtureを比較する, then raw hash/許可された差分が維持される。性能値だけ改善して描画結果が変わった変更を採用しない。
- [ ] debug/releaseのbackendとtoolchainが記録され、同じモードで比較される。JIT warm-up時間を隠した数値をcold start性能として載せない。
- [ ] 開発toolがruntime dependencyへ入っておらず、公開artifactに未許諾asset/秘密情報/絶対ローカルpathがない。
- [ ] 後続の実装PR/releaseは最新HEADのrequired CI Green、未解決P1なし、独立Approve相当レビューを確認する。レビュー実施モデル/設定が記録され、指定モデルを実行できない場合は未実施とする。
- [ ] 実行command、対象、PASS/FAIL/未実行が成果物へ載っている。background jobはrunning/completed/failedとrun idが記録され、起動だけで完了にしない。

## テスト計画

- 空のconsumerから公開libraryを導入し、Native/JSでbasic_drawingを実行する。
- fault injectionによるrelease gateの拒否テストを実行する。
- 最適化前後の画素hash比較とperformance report生成を実行する。
- 公開artifactの検査（開発tool混入、未許諾asset、秘密情報、絶対path）を実行する。
- CI集約結果のfail-closed動作（skip/cancel/missing）を確認する。
- publish/deployは実行せず、手順とmanifestの検証までを行う。

## リスク

- ベンチ成功を正しさの代用にすると、画素差のある最適化を採用する。画素hashを採用条件に含める。
- shared CIのノイズで一律fps gateは誤検知する。baseline後の相対退行gateと専用runnerを検討する。
- 未対応機能・targetを隠した配布は利用者の誤認を招く。release manifestとREADMEで明示する。
- 開発toolやassetの混入は配布物の安全性・ライセンスに影響する。検査をrelease前の必須手順にする。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- preview配布: 対応範囲、target別検証結果、既知差分を明記したrelease manifestを追加する。

## 根拠

- [上流benchmark群](https://github.com/shiguredo/raden/tree/afb752e17a69fef8af981251b68de22a7597ff01/benches)
- [上流の描画経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [上流JITと測定例](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)
- [MoonBit CLI reference](https://docs.moonbitlang.com/en/stable/toolchain/moon/commands.html)

## 注記

- 検証状態: 完了 (2026-10-17 実施)。publish/deploy は未実行。
  - `scripts/run_checks.sh` + `check_gate.py`: required 6 job の
    fail-closed 集約。fault injection 8 ケース全件拒否を実測。
  - `conformance/run_bench.sh`: 13 fixture × cold/warm、p50/p95、
    hash gate 付きレポート。baseline: native release、
    720p/1080p で candidate は oracle の約 3〜7x (目標は
    計測後に固定する方針のため budget 未設定)。
  - `consumer/` + `run_consumer_test.sh`: 独立 module が
    moon work 経由で公開 API のみ使用し native/js 両方で描画成功。
  - `release/manifest.json` + `inspect_artifact.sh`: 宣言範囲と
    artifact 検査 (200 files、混入/秘密情報なし)。
  - `docs/mutation-and-negative-controls.md`: 負の対照一覧と
    mutation survivor の分類方針。
- 本Issueは [issues/README.md](../README.md) のM5（実用化）に含まれる。performance予算はbaseline計測後に固定する。
- 2026-10-16: polish-issue で実装可能な形式へ整備。issues/open から移動。内容は計画作成時のもので、実装・検証は未実行
