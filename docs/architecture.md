# raden.mbt アーキテクチャ

作成日: 2026-10-17

## 目的

`shiguredo/raden` (上流 commit `afb752e17a69fef8af981251b68de22a7597ff01`)
の CPU ベクター描画を MoonBit で実装する。FFI ラッパーではなく、
パス処理・ラスタライズ・合成・ペイントを MoonBit へ移植する。
同一の描画コアからヘッドレス画像・ブラウザ表示・(将来) ネイティブ表示を提供する。

## パッケージ構成

```text
moon.mod                  # モジュール gpui-mbt/raden。preferred_target = "native"
upstream.lock.json        # 上流 SHA・toolchain・対応 target の固定記録
docs/                     # 本書・API対応表・既知差分表
LICENSE                   # Apache-2.0 + NOTICE (上流出典)

# 公開ファサード (ルートパッケージ gpui-mbt/raden)
image.mbt                 # Image (幅・高さ・stride・format・所有バッファ)
style.mbt                 # Rgba32 / CompOp / FillRule / StrokeCap / StrokeJoin
geometry.mbt              # Point / Rect / Circle / Ellipse / RoundRect / Triangle / Line / Arc
matrix.mbt                # Matrix2D (アフィン変換)
path.mbt                  # Path / PathCmd (move/line/quad/conic/cubic/close)
context.mbt               # Context / PipelineRuntime / save スタック
error.mbt                 # RadenError (InvalidInput / UnsupportedFeature / ResourceLimit)
edge_builder.mbt          # Path → 線分平坦化 (非公開実装)
stroke.mbt                # stroke_to_fill (cap/join/miter/dash、非公開実装)
gradient.mbt              # Gradient (linear/radial/conic) + LUT-256 + PreparedGradient
pattern.mbt               # Pattern (Nearest/Bilinear、Pad/Repeat/Reflect、スナップショット)
blit.mbt                  # blit_image_rect (ソース→宛先の Nearest 転送)
bmp.mbt                   # BMP 書き出し (検証用)

# font パッケージ (gpui-mbt/raden/font)
font/                     # TrueType/OpenType パース・グリフ輪郭・限定 shaping。
                          # pure: Bytes in → Path/メトリクス out。fs は host 責務

# 内部パッケージ (公開 API ではない)
internal/pixel/           # パックドピクセル演算・合成プリミティブ (UInt ベース)
internal/raster/          # AnalyticRasterizer (エッジ→カバレッジ)

# 実行入口
conformance/runner/       # fixture → .raw/.meta.json を生成する native 専用 cmd
examples/scenes/          # 上流 example scene の host 非依存移植
examples/raden-demo/      # ヘッドレス CLI (raw + meta 出力)
examples/browser/         # Vector Playground。ffi.mbt が JS export 層、
                          # site/ が static host (DOM/canvas 転送のみ)、
                          # e2e/ が chromium + node による検証
scripts/                  # .mbtx 自動化 (smoke / conformance)

# 比較基盤
conformance/rust-oracle/  # 上流 Rust 実装を呼ぶ独立 CLI (SHA 固定)
conformance/fixtures/     # 入力 fixture (raden.fixture.v1)。text op は
                          # shapes (glyph id/cluster/advance/offset) を meta で比較
conformance/fonts/        # 検証用フォント (SourceSans3-Regular、hash/pin 固定)
conformance/reference/    # oracle 生成物 (gitignore)
conformance/results/      # candidate 生成物 (gitignore)
```

公開具象型はすべてルートパッケージに置く。`internal/*` は
primitive 値 (UInt・タプル列) だけを受け取る低レベルアルゴリズムとし、
ルート型に依存させない (循環依存の防止と、内部 API の露出防止)。

## 所有権とメモリの方針

- `Image` はバッファを所有する。`data()` で読み取り専用の `BytesView` を
  返す。上流の `data_ptr_mut` 相当の無制限可変アクセスは公開しない。
- `Context` は `Image` と `PipelineRuntime` への参照を保持する
  (GC 言語のため借用期ではなく所有構造体フィールド)。
- `PipelineRuntime` は上流では JIT コンパイルキャッシュだが、
  移植版は JIT を持たない。スカラ合成の workspace/dispatch 境界として残し、
  JIT を持たないことは `docs/api-compatibility.md` で非互換として明示する。

## バックエンド方針

- 初期対応 target は `native` と `js`。
- wasm / wasm-gc / Windows / macOS Intel は `upstream.lock.json` で
  `not_verified` / `out_of_scope` と記録し、対応済みを詐称しない。
- OS・ブラウザ DOM・ファイル I/O・時計はホスト層 (conformance/runner、
  examples の host) に限定し、描画コアへ持ち込まない。

## エラー分類

`RadenError` を以下に分類する:

- `InvalidInput`: 非有限値・負の寸法・不正 stride 等、呼び出し側の入力ミス
- `UnsupportedFeature`: 未実装の format・transform・command。
  黙った no-op にせず必ずエラーか未対応 status にする
- `ResourceLimit`: 寸法×BPP・パス点数・再帰深度などの上限超過

入力は描画前に検証し、1 コマンドの失敗が部分書き込みにならないことを目指す
(上流が panic や過大確保になる入力は、安全なエラーとの意図的差分として
`docs/known-differences.md` に記録する)。

## 描画パイプライン (上流との対応)

上流は Cranelift JIT で `fill_rect` / `fill_path` / sweep / comp op を生成する。
移植版は同じ観測結果をスカラで実装する:

1. `fill_rect` (identity): `clip_rect` でクリップした整数ボックスへ
   スカラ合成を行単位で適用する。
2. `fill_path`: `edge_builder` で Path を線分に平坦化 →
   `internal/raster` の analytic rasterizer (セルバッファ + prefix sum sweep)
   でカバレッジ → span 合成。
3. `stroke_path`: `stroke.mbt` の `stroke_to_fill` でストロークを
   塗りつぶしパス (左右輪郭 + Join + Cap) に変換し、fill 状態を一時的に
   ストロークスタイルへ差し替えて `fill_path` する (上流と同じ手法)。
4. グラデーション/パターンは `PreparedGradient` / `PreparedPattern` に
   逆行列を畳み込み、span fetch → カバレッジ合成で描画する。
   上流の quirk を再現する:
   - `fill_rect` (identity・アルファ 1) はスタイル別専用パスを取り、
     グラデーションは comp_op を無視して常に SrcOver 相当で書く。
   - スタイル付き `fill_path` は span_cov パイプラインが comp_op を
     参照しないため、常に SrcOver 合成になる。
   - パターン `fill_rect` は SrcCopy/SrcOver のみ (それ以外はエラー)。
   - 実効アルファ < 1 または非 identity 行列の矩形は fill_path へ
     フォールバックする。
5. 合成式は JIT 生成コードの整数演算をそのまま移す。
   `(x * 257 + 257) >> 16` の div255、`256 - a` の逆アルファ、
   `(v + 0x80 + (v >> 8)) >> 8` の scale を使い、
   一般的な浮動小数点ブレンド式へ置き換えない。

## 比較基盤

- `conformance/rust-oracle` が上流 API を実呼び出しし、
  canonical な premultiplied RGBA8 raw と `.meta.json` を出す。
- 移植版は `conformance/runner` が同じ fixture を実行し同形式で出力する。
- oracle の `compare` が expected manifest に基づき fail-closed で照合する。
  実行入口は `scripts/conformance.mbtx`。
- browser 側は同じ canonical raw を `manifest.json` の sha 台帳と照合する。
  参照 fetch 本体の sha を manifest 値と突き合わせて旧 manifest を
  検知する仕組みも UI 側に持つ (偽 PASS の防止)。
