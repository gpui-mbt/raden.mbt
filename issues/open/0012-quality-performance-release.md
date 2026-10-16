---
id: RADEN-0012
status: open
priority: P2
milestone: M5
depends_on: [RADEN-0002, RADEN-0008]
---

# 回帰ゲート・性能測定・preview配布を整える

## 目的

描画結果が合うスカラ実装を基準に、品質と性能を測定できる状態へ進める。未対応の範囲を隠さず、宣言した範囲を独立consumerが利用できるpreviewとして配布する。

## 実装方針

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

## 成果物

- 共通test/benchmark script、CI matrix、fail-closedな集約結果。
- 正常/不正入力corpus、負の対照、mutationの評価記録。
- 固定入力と実行条件を持つperformance reportと改善前後の画素比較。
- release manifest、公開API/対応表、独立consumer、SBOMまたは依存/asset台帳、release手順。

## テストと受入条件

1. 公開libraryを空のconsumerから導入し、Native/JSで最低basic_drawingを実行する。リポジトリ内の非公開helperや未公開ローカル依存がなくても動くこと。
2. fault injectionでcandidate fail、oracle fail、job cancel、結果欠落、古いSHA、意図的な1画素差を入れ、release gateがすべて拒否すること。
3. 最適化前後でrequired fixtureのraw hash/許可された差分が維持されること。性能値だけ改善して描画結果が変わった変更を採用しない。
4. debug/releaseのbackendとtoolchainを記録し、同じモードで比較する。JIT warm-up時間を隠した数値をcold start性能として載せない。
5. 開発toolがruntime dependencyへ入っていないこと、公開artifactに未許諾asset/秘密情報/絶対ローカルpathがないことを検査する。
6. 後続の実装PR/releaseは最新HEADのrequired CI Green、未解決P1なし、独立Approve相当レビューを確認する。レビュー実施モデル/設定を記録し、指定モデルを実行できない場合は未実施とする。
7. 実行command、対象、PASS/FAIL/未実行を成果物へ載せる。background jobがある場合は観測したrunning/completed/failedとrun idを記録し、起動だけで完了にしない。

## 分割と依存

M0/M1の時点から小さなCI gateを追加し、M5でまとめて品質基盤を作らない。本Issueはmutation/performance/releaseの拡張を担当する。任意機能の完成を待たず、宣言済み範囲のpreviewを検証できる構成にする。

## 対象外

未測定の速度保証、upstreamへの無断push、全target一括公開、スコアだけでの品質評価、デモ表示のfpsとCPU描画速度の混同を含めない。

## 根拠

- [上流benchmark群](https://github.com/shiguredo/raden/tree/afb752e17a69fef8af981251b68de22a7597ff01/benches)
- [上流の描画経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [上流JITと測定例](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)
- [MoonBit CLI reference](https://docs.moonbitlang.com/en/stable/toolchain/moon/commands.html)

検証状態: 未実行（実装計画）。publish/deployも未実行。
