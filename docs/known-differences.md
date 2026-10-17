# 既知差分表 (intentional differences)

上流の観測結果と意図的に異なる点を記録する。互換テストの `pass` 扱いにしない。
各行に「理由・最小再現・上流ソース・状態」を付ける。

| # | 差分 | 上流挙動 | 移植版挙動 | 理由 | 上流 source | 状態 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 過大寸法の `Image::new` | `stride * height` の `Vec<u8>` 確保で OOM / panic の可能性 | `RadenError::ResourceLimit` エラー (描画前検証) | 過大確保を安全なエラーに置き換える | src/api/image.rs | safety-tested |
| 2 | 非有限・負寸法 | `as i32` 変換で飽和 (Rust 1.45+ の挙動) | 同様に飽和させるが NaN 座標は InvalidInput 扱いを検討 | NaN 由来の不定動作を避ける | src/api/context.rs clip_rect | open |
| 3 | `fill_path` on A8 | `assert_ne!` で panic | `RadenError::UnsupportedFeature` エラー | panic を再現せず安全なエラーに | src/api/context.rs | safety-tested |
| 4 | A8 での gradient/pattern fill_rect | panic!("pattern and gradient fills are not supported for A8 destination") | `RadenError::UnsupportedFeature` エラー | 同上 | src/api/context.rs | safety-tested |
| 5 | JIT パイプライン | Cranelift IR 生成・実行・キャッシュ | スカラ参照実装 | JIT は初期スコープ外。観測結果の一致を目指す | src/pipeline/ | by design |
| 6 | `smooth_quad_to` / `smooth_cubic_to` 前置条件違反 | `expect` で panic | `RadenError::InvalidInput` エラー | panic を再現しない | src/api/path.rs | safety-tested |
| 7 | `conic_to` w <= 0 | `assert!(w > 0.0)` で panic | `RadenError::InvalidInput` エラー | 同上 | src/api/path.rs | safety-tested |
| 8 | ソース == 宛先の blit | 借用規則により表現不能 | ソースをスナップショットして転送 | MoonBit では同一 `Image` を渡せてしまうため、書き込みによる読み込み汚染を防ぐ | src/api/blit.rs | safety-tested |
| 9 | 非対応ソース形式・合成 op の blit | `assert!` で panic | `RadenError::InvalidInput` エラー | panic を再現しない | src/api/blit.rs | safety-tested |
| 10 | パターン `fill_rect` で SrcCopy/SrcOver 以外 | `assert!` で panic | `RadenError::UnsupportedFeature` エラー | 同上 (空矩形は上流同様チェックを通過) | src/api/context.rs | safety-tested |
| 11 | `Context::fill_text` / `stroke_text` | `Context` のメソッド | `font::fill_text(ctx, ...)` / `font::stroke_text(ctx, ...)` 自由関数 | MoonBit ではパッケージ外の型にメソッドを追加できない。描画経路 (全グリフを 1 Path に合成して fill/stroke) は同一 | src/api/context.rs | safety-tested |
| 12 | `raden_player` の表示フォント | macOS の `/System/Library/Fonts/Helvetica.ttc` | vendored `SourceSans3-Regular.ttf` (72/32px) | OS フォント依存を避け、CI と全 target で同じ glyph を得る。adapter fixture の pixel parity のみ主張し upstream example parity は not_verified | examples/raden_player.rs | by design |
| 13 | `raden_player` の actual FPS 表示 | wall clock から実測した FPS | target FPS 固定 (headless では 120.0) | 実時間に依存する golden を作らない。表示文字列は決定化される | examples/raden_player.rs | by design |

`safety-tested` は「上流 panic ではなく安全なエラーになること」を
wbtest / corrupt corpus で確認した状態であり、互換 pass ではない。
`open` は未確認の意図的差分として残す。
