# API 対応表

上流 `shiguredo/raden` @ `afb752e17a69fef8af981251b68de22a7597ff01` の
公開 API と移植版の対応関係。status の語彙:

- `not_implemented` : 未実装
- `implemented_unverified` : 実装済みだが fixture 比較未検証
- `pass` : oracle との生ピクセル一致を確認
- `fail` : 差分を検出
- `unsupported_upstream` : 上流の制約を再現しない (意図的差分)
- `not_applicable` : MoonBit では対象外 (JIT 内部・unsafe ポインタ等)

| 上流 symbol | 上流 source | MoonBit API | status | 担当 Issue | fixture / 備考 |
| --- | --- | --- | --- | --- | --- |
| `PixelFormat::Prgb32` | src/pixel/format.rs | `PixelFormat::Prgb32` | pass | 0003 | prgb32 fixture 群 |
| `PixelFormat::Xrgb32` | src/pixel/format.rs | `PixelFormat::Xrgb32` | pass | 0003 | fill_xrgb32_4x3 fixture |
| `PixelFormat::A8` | src/pixel/format.rs | `PixelFormat::A8` | pass | 0003 | fill_rect_a8_6x4 fixture。上流の A8 対応範囲は限定的 |
| `PixelFormat::bytes_per_pixel` | src/pixel/format.rs | `PixelFormat::bytes_per_pixel` | implemented_unverified | 0003 | |
| `premultiply_rgba` | src/pixel/mod.rs | `Rgba32::to_prgb32` / `premultiply_rgba` | pass | 0003 | (r*a+128)/255 の丸め、全 fixture が経由 |
| `Image::new` | src/api/image.rs | `Image::new` | pass | 0003 | 上限・overflow は ResourceLimit エラー |
| `Image::{width,height,stride,format}` | src/api/image.rs | 同名メソッド | pass | 0003 | |
| `Image::data` | src/api/image.rs | `Image::data` (BytesView 返却) | pass | 0003 | 読み取り専用 |
| `Image::data_mut` | src/api/image.rs | 非公開 | not_applicable | 0003 | 所有 buffer の無制限貸出は移植しない |
| `Image::data_ptr_mut` | src/api/image.rs | なし | not_applicable | 0003 | unsafe ポインタは移植対象外 |
| `Image::write_to_file` | src/api/image.rs | `write_bmp` 相当 | not_implemented | 0008 | ファイル I/O は host 層 |
| `Rgba32::new/rgb/r/g/b/a` | src/api/style.rs | `Rgba32` | pass | 0003 | 内部表現 0xAARRGGBB |
| `Rgba32::{is_opaque,is_transparent,to_prgb32}` | src/api/style.rs | 同名 | pass | 0003 | |
| `CompOp` (全 29) | src/api/style.rs | `CompOp` | pass | 0003/0007 | comp_ops_box_8x29 / comp_ops_span_42x35 fixture で全 op を網羅。ColorDodge/ColorBurn は上流同様 SIMD 経路 (f32) とスカラ末尾経路 (整数) をラン長で使い分ける |
| `FillRule` | src/api/style.rs | `FillRule` | pass | 0005 | fill_path_evenodd_star / nonzero_overlap fixture |
| `StrokeCap` | src/api/style.rs | `StrokeCap` | pass | 0006 | stroke_line_round_square/stroke_polyline_round fixture |
| `StrokeJoin` | src/api/style.rs | `StrokeJoin` | pass | 0006 | bevel/round/miter_clip fixture |
| `Matrix2D` | src/api/matrix.rs | `Matrix2D` | pass | 0004 | fill_path_matrix fixture (translate/scale/rotate/reset)。post_* 系は scene_blit_clip_pattern と set_matrix fixture で検証 |
| `Point` | src/api/path.rs | `Point` | pass | 0004 | |
| `Path` | src/api/path.rs | `Path` | pass | 0004 | move/line/quad/cubic/close/add_circle は fixture 済み。conic/smooth_quad/smooth_cubic/arc_to は scene_blit_clip_pattern fixture で検証済み |
| `PathCmd` | src/api/path.rs | `PathCmd` | pass | 0004 | |
| `Context::new` | src/api/context.rs | `Context::new` | pass | 0003 | |
| `Context::{save,restore}` | src/api/context.rs | 同名 | pass | 0003 | 空 restore は no-op (上流準拠)。scene_stroke_drawing / scene_blit_clip_pattern で検証 |
| `Context::{set_comp_op,comp_op}` | src/api/context.rs | 同名 | pass | 0003 | |
| `Context::{set_fill_rule,fill_rule}` | src/api/context.rs | 同名 | pass | 0005 | |
| `Context::set_fill_style` | src/api/context.rs | `set_fill_style` | pass | 0003 | |
| `Context::set_stroke_style` | src/api/context.rs | `set_stroke_style` | pass | 0006 | stroke_* fixture |
| `Context::{set_stroke_style_gradient,set_stroke_style_pattern}` | src/api/context.rs | 同名 | pass | 0007 | stroke_gradient_line fixture。fill_state を一時交換して描画 |
| `Context::set_fill_style_gradient` | src/api/context.rs | `set_fill_style_gradient` | pass | 0007 | grad_* fixture。設定時点の内容をスナップショット |
| `Context::set_fill_style_pattern` | src/api/context.rs | `set_fill_style_pattern` | pass | 0007 | pattern_* fixture。画像バイトをスナップショット |
| `Context::set_global_alpha / fill_alpha / stroke_alpha` | src/api/context.rs | 同名 | implemented_unverified | 0003 | 0..=1 clamp |
| `Context::{translate,scale,rotate,rotate_around,skew}` | src/api/context.rs | 同名 | pass | 0004 | 後乗算。rotate_around は blit_rotate fixture、skew は scene_blit_clip_pattern で検証 |
| `Context::{post_translate,post_scale,post_rotate,post_skew,post_transform}` | src/api/context.rs | 同名 | pass | 0004 | 前乗算。post_translate/post_rotate/post_skew は scene_blit_clip_pattern、post_transform は各 set_matrix fixture で検証 |
| `Context::{reset_matrix,apply_matrix,user_to_meta}` | src/api/context.rs | 同名 | implemented_unverified | 0004 | |
| `Context::{clip_to_rect,restore_clipping}` | src/api/context.rs | 同名 | pass | 0003 | clip_to_rect + restore_clipping は scene_blit_clip_pattern で検証 |
| `Context::{fill_rect,fill_all}` | src/api/context.rs | 同名 | pass | 0003 | fill_rect_*/fill_all_* fixture |
| `Context::{clear_rect,clear_all}` | src/api/context.rs | 同名 | pass | 0003 | comp op 非依存、デバイス座標 |
| `Context::fill_path` | src/api/context.rs | `fill_path` | pass | 0005 | fill_path_* fixture。A8 宛先は UnsupportedFeature (上流 panic と差分) |
| `Context::{fill_circle,fill_ellipse,fill_round_rect,fill_triangle,fill_polygon,fill_pie}` | src/api/context.rs | 同名 | pass | 0005 | fill_circle_10x10 fixture、fill_path 経由 |
| `Context::stroke_path` | src/api/context.rs | `stroke_path` | pass | 0006 | stroke→fill 変換。stroke_* fixture |
| `Context::{stroke_rect,stroke_line,stroke_circle,stroke_ellipse,stroke_round_rect,stroke_triangle,stroke_polygon,stroke_polyline}` | src/api/context.rs | 同名 | pass | 0006 | stroke_* fixture |
| `Context::{set_stroke_width,cap,join,miter_limit,dash}` | src/api/context.rs | 同名 | pass | 0006 | stroke_dash_line/stroke_miter_limit fixture |
| `Context::{blit_image_at,blit_image_rect}` | src/api/context.rs | 同名 | pass | 0007 | blit_image_* fixture。SrcOver/SrcCopy、nearest のみ |
| `Context::{fill_text,stroke_text}` | src/api/context.rs | `font::fill_text` / `font::stroke_text` | pass | 0011 | パッケージ外メソッドを持てないため自由関数。text_fill_* / text_stroke_* / font_shaping fixture |
| `Gradient` (linear/radial/conic) | src/api/gradient.rs | `Gradient` | pass | 0007 | LUT-256 + 8.8 固定小数点補間。linear は 16.48 累積、radial は f32 距離、conic は上流相当の fast atan2。radial の LUT index 丸めはオラクル観測で truncate (再現) |
| `GradientStop` | src/api/gradient.rs | `GradientStop` | pass | 0007 | 同一 offset 停止点・0/1 停止点・退化勾配を fixture 済み |
| `ExtendMode` | src/api/gradient.rs | `ExtendMode` | pass | 0007 | Pad/Repeat/Reflect。負座標繰り返しも fixture 済み |
| `Pattern` / `PatternFilter` | src/api/pattern.rs | `Pattern` / `PatternFilter` | pass | 0007 | Nearest/Bilinear。負 origin・非正方・透明端・変換行列を fixture 済み |
| `FontData` / `FontFace` / `Font` | src/font/ | `font::FontData` / `FontFace` / `Font` | pass | 0011 | text_* fixture。shape は glyph/cluster/advance/offset を meta で厳密比較 |
| `PipelineRuntime` | src/pipeline/runtime.rs | `PipelineRuntime` (スカラ workspace) | implemented_unverified | 0003 | JIT キャッシュではない |
| JIT コンパイル API (`get_or_compile_*`) | src/pipeline/ | なし | not_applicable | 0001 | JIT 非対応、スカラ参照実装で代替 |
| `codec::bmp` | src/codec/bmp.rs | BMP 書き出し相当 | not_implemented | 0009 | host/codec 層として別途 |

## パブリック API でないもの (非互換として明記)

- `pipeline::compiler` 以下の JIT IR 生成関数群: 移植しない (not_applicable)。
- `Image::data_ptr_mut` / `data_mut` の無制限可変アクセス: 所有バッファを
  直接公開しない (安全性優先。必要なら将来ゼロコピー経路を別途実証)。
- `PipelineRuntime::get_or_compile*`: JIT は持たない。

## 演算 × ペイント × 形式の対応行列 (上流準拠)

| エントリ | ペイント | Prgb32 | Xrgb32 | A8 |
| --- | --- | --- | --- | --- |
| `fill_rect` (identity, α=1) | 単色 | 全 29 op | 全 29 op | Clear/SrcCopy/SrcOver/Plus |
| `fill_rect` (同上) | グラデーション | SrcOver 相当 (op 無視・上流 quirk) | 同左 | UnsupportedFeature |
| `fill_rect` (同上) | パターン | SrcCopy/SrcOver のみ | 同左 | UnsupportedFeature |
| `fill_rect` (α<1 または非 identity) | 全ペイント | fill_path へフォールバック | 同左 | 単色のみ / スタイルはエラー |
| `fill_path` | 単色 | 全 29 op | 全 29 op | UnsupportedFeature |
| `fill_path` | グラデーション/パターン | SrcOver 相当 (span_cov は op 無視・上流 quirk) | 同左 | UnsupportedFeature |
| `stroke_path` | 全ペイント | ストローク→塗りに変換し fill_path と同じ | 同左 | UnsupportedFeature |
| `blit_image_*` | - | SrcCopy/SrcOver | SrcCopy/SrcOver | SrcCopy/SrcOver |

ColorDodge / ColorBurn は上流同様にラン長で使い分ける:
ランの先頭 `count & ~3` ピクセルは SIMD 相当 (f32 式)、末尾 `count % 4`
はスカラ相当 (整数式)。SoftLight は両経路とも f32。

## フォント形式・lookup の対応表 (上流準拠)

上流 `src/font/` が受理する範囲のみを移植対象とする。

| 項目 | 対応 | 備考 |
| --- | --- | --- |
| sfnt (TrueType outlines, `glyf`/`loca`) | 対応 | 0x00010000 / `true` シグネチャ |
| CFF / CFF2 (PostScript outlines) | 非対応 (上流も非対応) | 必須テーブル不足として FontError |
| `cmap` format 4 / 12 | 対応 | 他 format は未対応 (上流同様) |
| `glyf` simple glyph | 対応 | quadratic curve を Path へ変換 |
| `glyf` compound glyph | 対応 | 再帰深さ・cycle・点数上限あり |
| GSUB Single (type 1) | 対応 | `liga` / `clig` / `kern` 以外の feature 指定は対象外 |
| GSUB Ligature (type 4) | 対応 | 部分適用 ("ffi" → `f_f` + `i`) は上流同様 |
| GSUB その他 lookup type | 非対応 (上流も非対応) | 対象 lookup は黙ってスキップ |
| GPOS Single (type 1) | 対応 | x_advance / x_offset のみ使用 |
| GPOS Pair (type 2) | 対応 | kern pair。他の位置調整は上流未対応 |
| GPOS その他 lookup type | 非対応 (上流も非対応) | 同上 |
| feature `liga` / `kern` / `clig` | 対応 | `FontFeatureSettings` で個別 ON/OFF |
| script / language 選択 | 非対応 (上流も非対応) | 既定の script_list 先頭を使用 |
| 縦書き (`vhea`/`vmtx`) | 非対応 (上流も非対応) | |
| 可変フォント (fvar/gvar) | 非対応 (上流も非対応) | |
| COLR / SVG / bitmap グリフ | 非対応 (上流も非対応) | |

cluster の単位は UTF-8 byte offset (上流 `char_indices()` 準拠)。
shape 結果は conformance meta の `shapes` フィールドで
glyph id / cluster / advance / offset を oracle と厳密比較する。
