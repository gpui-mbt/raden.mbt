# raden.mbt 実装計画

作成日: 2026-10-16

状態: 計画作成済み。以下の12件はすべて polished（`issues/polished/`）。計画作成時点で移植先にはルートの README.md のみがあり、MoonBit実装、ビルド設定、CI、デモはない。本文中の配置・API・コマンド・性能予算は今後実装する設計であり、動作確認済みの機能ではない。Issue本体は実装可能な形式へ整備済みだが、実装・検証は未着手。

## 1. 目的と設計判断

`shiguredo/raden` のCPUベクター描画をMoonBitで実装し、同じ描画コアからヘッドレス画像、ブラウザのVector Playground、gpui.mbtのNative表示を提供する。単なるFFIラッパーではなく、パス処理、ラスタライズ、合成、ペイントをMoonBitへ移す。

1. 最初の縦切りは **Prgb32画像 → SrcCopy/SrcOverの矩形 → 上流basic_drawingと同じ1280×720画像 → Rust oracleとの画素比較 → ブラウザ表示** とする。曲線やフォントを待たずに成果を見せる。
2. CraneliftのIR生成・JIT・SIMDを初期スコープにしない。まずスカラの`PipelineRuntime`で描画結果を合わせ、最適化可能な境界だけ確保する。上流の性能値を移植版の性能目標達成と混同しない。
3. 比較元は **実際のRustネイティブ実行** とする。上流CargoにはCraneliftの必須依存があるため、Rust版がそのままWASMで動く前提は置かない。ブラウザでは固定Rust参照画像とMoonBitのライブ描画を比較し、参照画像であることを明示する。
4. NativeとJavaScriptを初期の対応targetにする。Linux x86_64とmacOS Apple Siliconを対象とし、Mac Intelは対象外。Windows、Wasm/WasmGCは後続の個別検証とし、未実行のtargetを対応済みにしない。
5. gpui.mbt、DOM、Canvas、ファイルI/O、時計、OSイベントはホスト層へ分離する。CPU描画コアにGPU・ブラウザ・SDL・Nodeの依存を入れない。ブラウザCanvasにはMoonBitが計算したピクセルを転送し、Canvasの図形描画で移植を代替しない。
6. 互換基準は固定上流の観測結果とする。ただしpanic、過大確保、不正入力の危険な挙動は再現必須にせず、安全なエラーとの意図的差分として記録する。上流制約の改善は別の変更として扱う。

## 2. 上流の固定基準

| 項目 | 計画作成時の確認値 |
| --- | --- |
| Repository | `shiguredo/raden` |
| Commit | `afb752e17a69fef8af981251b68de22a7597ff01` |
| Cargo package | `raden` / `2026.2.0` |
| Cargo rust-version | `1.94`。依存を含めてビルドできるツールチェーンはRADEN-0001で実測・固定する |
| ライセンス表記 | Apache-2.0。移植コードと個別アセットの出典管理はRADEN-0001 |
| 移植先の調査基点 | `be6ce812cec10c5170b4ec98627cf3c0af0bf124` |

上流の`main`やWeb検索のキャッシュを混ぜず、同じSHAのREADME・ソース・Cargo.lockで確認する。READMEと実装が異なる場合は実行結果、該当ソース、差分理由を並記する。

## 3. Issue一覧と依存関係

`P1/P2`はこの計画での実装優先度であり、コードレビュー上の不具合重大度ではない。`depends_on`は着手に必要な土台を表し、全機能の完成待ちを意味しない。

| ID | 実装単位 | 優先度 | 土台となるIssue |
| --- | --- | --- | --- |
| [RADEN-0001](polished/0001-bootstrap-and-port-contract.md) | ツールチェーン、API棚卸し、ライセンス、target分離 | P1 | なし |
| [RADEN-0002](polished/0002-rust-oracle-and-conformance.md) | 固定Rust oracle、fixture、差分・偽陽性防止 | P1 | 0001 |
| [RADEN-0003](polished/0003-image-pixel-compositing-context.md) | Image、ピクセル合成、Context、矩形描画 | P1 | 0001 |
| [RADEN-0004](polished/0004-geometry-paths-affine.md) | 幾何、Path、行列、平坦化 | P1 | 0001 |
| [RADEN-0005](polished/0005-analytic-rasterizer.md) | 解析的ラスタライズ、coverage、形状塗り | P1 | 0003、0004 |
| [RADEN-0006](polished/0006-strokes-and-dashes.md) | stroke-to-fill、cap/join、dash | P2 | 0005 |
| [RADEN-0007](polished/0007-gradients-patterns-blit.md) | Gradient、Pattern、Blit、合成モード拡充 | P2 | 0005 |
| [RADEN-0008](polished/0008-upstream-examples-headless.md) | 上流example全8本の追跡、共通scene、ヘッドレスCLI | P1 | 0002、0003 |
| [RADEN-0009](polished/0009-browser-vector-playground.md) | Web表示、操作、参照画像との比較、公開準備 | P1 | 0002、0008 |
| [RADEN-0010](0010-gpui-native-host.md) | gpui.mbt画像表示、イベント・寿命管理 | P2 | 0008 |
| [RADEN-0011](0011-fonts-and-shaping.md) | TrueTypeアウトライン、GSUB/GPOS、font_shaping | P2 | 0005、0006 |
| [RADEN-0012](0012-quality-performance-release.md) | 回帰ゲート、turtles/hotpath、性能、配布 | P2 | 0002、0008 |

## 4. 到達点

| Milestone | 見える成果 | 必要な完了条件 |
| --- | --- | --- |
| M0: 基盤 | target別smokeとRust参照を再生成できる | 0001、0002のoracle単体経路。まだMoonBit互換とは称さない |
| M1: 最初のデモ | `basic_drawing`をNativeとJSで生成しWeb表示 | 0003、0008/basic、0009/basic。生ピクセル比較PASS |
| M2: Vector Playground | 曲線、穴、変換、clipを操作・可視化 | 0004、0005、0009の操作追加。preset以外は参照なしを表示 |
| M3: 描画拡充 | stroke、gradient、pattern、blit、tiger、固定時刻animation | 0006、0007、0008の対象fixtureごとの比較。tigerは出典確認後 |
| M4: Native統合・テキスト | gpui画像表示、font_shaping | 0010と0011は別々に判定。OS実機テストとフォント条件を明記 |
| M5: 実用化 | 測定済み性能と対応表を持つpreview配布 | 0012。未対応機能を隠さず、宣言した範囲だけを配布 |

最初の作業順は`0001 → 0002のRust側と0003を並行 → 0008/basic → 0009/basic`。0004は0003と並行できる。後段Issueを全部完了しないとM1を出せない計画にはしない。

## 5. 共通の合格基準

1. 同じfixture、サイズ、seed、frame、入力hash、上流SHA、candidate SHA、target、ツールチェーンを成果物へ埋め込む。入力・参照・実行証跡のどれかが欠ければ未検証とする。
2. statusは`not_implemented / implemented_unverified / pass / fail / unsupported_upstream / blocked_environment`を区別する。`pass`以外を互換成功数へ足さない。
3. 最初の整数矩形・色・合成は生ピクセルの完全一致を要求する。曲線・浮動小数点の許容差はfixture単位で根拠と承認を必要とし、一律の「見た目が近い」判定で逃げない。
4. 意図的に1色、1ピクセル、fill rule、行列順、alpha、clipを壊した負の対照で比較器がFAILになることを確認する。古い画像、サイズ違い、空画像で緑にならない。
5. 後続の実装PRは最新HEADのCI Green、未解決P1なし、独立したApprove相当レビューを必要とする。既存運用に合わせレビューは`gpt-6.1-sol / xhigh`を想定するが、実行できない場合は未実施を明記し代替結果を詐称しない。
6. デモのスクリーンショットは表示ホスト検証、生ピクセル比較は描画コア検証として分離する。ベンチ成功は正しさの代用にしない。

## 6. 初期スコープ外

Cranelift/JITの完全移植、RustバイナリのFFI呼出しだけによる実装完了、GPUレンダラー、gpui.mbtの全面置換、完全なSVG/CSS/Canvas互換、パスclip、CFF/CFF2/可変フォント、一般的な多言語組版、raw-player全体の移植、Mac Intel、上流への無断変更を含めない。将来必要なら独立Issueにする。

## 7. 根拠

- [上流Cargo](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/Cargo.toml)
- [公開API](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/src/lib.rs)
- [描画経路](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/RASTERIZE.md)
- [JITの演算・キャッシュ](https://github.com/shiguredo/raden/blob/afb752e17a69fef8af981251b68de22a7597ff01/docs/JIT.md)
- [上流example一覧](https://github.com/shiguredo/raden/tree/afb752e17a69fef8af981251b68de22a7597ff01/examples)
- [MoonBit FFI](https://docs.moonbitlang.com/en/stable/language/ffi.html)

実装、Rust oracle生成、MoonBitテスト、ブラウザ/Native E2E、性能測定、公開は計画作成時点ですべて未実行。
