# raden.mbt

MoonBit port of [shiguredo/raden](https://github.com/shiguredo/raden):
CPU 2D ベクターグラフィックスコア。

上流は Cranelift JIT ベースの Rust 実装。本リポジトリは同じ整数演算・
ラスタライズ規則をスカラコードで再現するネイティブ移植であり、
FFI ラッパーではない。

## 上流ピン

- upstream: `https://github.com/shiguredo/raden`
- SHA: `afb752e17a69fef8af981251b68de22a7597ff01` (`upstream.lock.json`)
- version: `raden 2026.2.0` / license: Apache-2.0

## ターゲット

- `native` (第一対象。macOS arm64 で検証済み、Linux x86_64 は CI のみ)
- `js` (moon test は両ターゲットで実行される。node v24 で検証済み)

## 構成

- ルートパッケージ `gpui-mbt/raden`: 公開 API
  (`Image`, `Rgba32`, `Context`, `Path`, `Matrix2D`, `CompOp`, `PixelFormat`)
- `internal/pixel`: パックドピクセル演算 (premultiply / Porter-Duff / A8)
- `internal/raster`: 解析的ラスタライザ (cell 蓄積 + sweep)
- `internal/sha256`: conformance 成果物のハッシュ計算
- `font/`: TrueType パース・glyph 輪郭・限定 GSUB/GPOS shaping
- `examples/scenes`: 上流 example の scene 移植 (host 非依存・決定的)
- `examples/raden-demo`: scene のヘッドレス CLI (raw + bmp + metadata 出力)
- `examples/manifest.json`: 上流 8 example の status 台帳 (host 別 status 付き)
- `conformance/`: Rust oracle、fixture、期待集合、比較レポート
- `docs/`: アーキテクチャ・API 対応表・既知差分

## テスト

```sh
moon test               # native: 75 tests
moon test --target js   # js: 58 tests
```

依存は `moonbitlang/async@0.22.4` (fs/時刻のみ。pure core は不使用)。

## conformance

Rust oracle (上流 crate を固定 SHA で実際に呼ぶ) と MoonBit candidate の
出力を生ピクセル完全一致で比較する。

```sh
conformance/run_conformance.sh            # candidate 生成 + 比較
conformance/run_conformance.sh --regen-oracle  # oracle 参照も再生成
```

- 入力: `conformance/fixtures/*.json` (fixture schema `raden.fixture.v1`)
- 期待集合: `conformance/expected.json` (`raden.expected.v1`)
- oracle 出力: `conformance/reference/` (`<id>.raw` + `<id>.meta.json`)
- candidate 出力: `conformance/candidate/` (同一形式、`generator: moonbit-candidate`)
- レポート: `conformance/report.json` (`gate: pass/fail`)

比較は fail-closed: 欠落・重複・空集合・旧 SHA・hash 不一致は全て失敗。
比較器自身の負の対照は `raden-oracle selftest` (13 control) が毎回検査する。
`text` fixture では描画ピクセルに加えて `shapes` メタデータ
(glyph id / cluster (UTF-8 byte index) / advance / offset) を厳密比較する。
95 fixture (pixel + shapes) が oracle と一致する。
詳細は `docs/architecture.md` と `issues/` を参照。

## 回帰ゲート / ベンチ / preview

```sh
scripts/run_checks.sh               # required job 集合 + gate 判定 (fail-closed)
scripts/run_checks.sh --with-bench  # 性能ベンチ込み
scripts/test_gate.sh                # gate の fault injection テスト
conformance/run_bench.sh [frames]   # oracle vs candidate の速度比較レポート
scripts/run_consumer_test.sh        # 独立 consumer 導入検証 (native/js)
release/inspect_artifact.sh         # 配布 artifact の検査
```

- CI 判定は `scripts/check_gate.py` が `ci/jobs/*.json` を集約する。
  required job の missing/fail/cancelled/skip は全て gate fail。
- bench は同一 fixture/size/frame を Rust native と MoonBit native で比較し、
  cold start と warm p50/p95 を分離。画素 hash 不一致なら gate fail。
- preview 配布範囲は `release/manifest.json` が宣言する。
  publish/deploy は実行していない。

## examples (ヘッドレス実行)

上流 example の scene は `examples/scenes` に host 非依存で移植済み
(描画定数・命令列は上流をそのまま転記、conformance/rust-oracle/src/scenes.rs
と同一内容)。`raden-demo` CLI で raw pixel + BMP + metadata を出力できる:

```sh
moon build examples/raden-demo
./_build/native/debug/build/examples/raden-demo/raden-demo.exe \
    --example basic_drawing --output /tmp/demo --headless
# => /tmp/demo/basic_drawing.raw (canonical RGBA8)
# => /tmp/demo/basic_drawing.bmp (top-down 32bpp BI_BITFIELDS)
# => /tmp/demo/basic_drawing.meta.json (sha256 等)

# animation は明示的な frame/fps で時刻が決まる (実時間不使用)
... --example animation --frame 30 --fps 60

# font_shaping は固定フォントを読み、conformance fixture と同じ scene を描く
... --example font_shaping --font conformance/fonts/SourceSans3-Regular.ttf
```

`examples/manifest.json` が上流 8 本の status を管理する
(ready 6 本 / blocked 2 本: tiger・raden_player。font_shaping は 2026-10-17 に
conformance fixture と同一の raw hash で ready 化)。
`examples/run_examples.sh` で ready 全件の raw hash と BMP decode 一致、
blocked の非 0 終了を検証できる。

## browser (Vector Playground)

`examples/browser` に static 配信可能な比較デモがある。
MoonBit JS ビルドの描画コアが live でレンダリングし、
Rust oracle の固定参照画像と canonical バイト列で比較する
(参照側はブラウザでのライブ実行ではない)。

```sh
./examples/browser/build.sh                    # site/ を生成
cd examples/browser/site && python3 -m http.server 8931
```

E2E 検証: `examples/browser/e2e` (`node unit.mjs` で純粋ロジック、
`node check.mjs` で headless Chromium による 30 項目の DOM/故障注入検証)。
詳細は `examples/browser/README.md`。

## 実装状況

| 領域 | 状態 |
| --- | --- |
| Prgb32/Xrgb32/A8 Image | 実装済み |
| 全 29 CompOp (+coverage) | oracle 完全一致 |
| fill_rect / fill_all / clear_rect / clip / matrix | oracle 完全一致 |
| fill_path (解析的ラスタライズ、NonZero/EvenOdd) | oracle 完全一致 |
| blit (SrcOver/SrcCopy, nearest) | oracle 完全一致 |
| stroke_to_fill (cap/join/miter limit/dash) | oracle 完全一致 |
| グラデーション (Linear/Radial/Conic) | oracle 完全一致 |
| パターン (Nearest/Bilinear、ExtendMode 全て) | oracle 完全一致 |
| 拡張パス命令 (smooth/conic/arc_to) | oracle 完全一致 |
| 上流 example scene 6 本 (font_shaping 含む) | oracle raw 一致 + BMP 検証 (manifest 管理) |
| font (TrueType glyf + GSUB/GPOS 限定) | oracle shape/pixel 一致 |
| fill_text / stroke_text | oracle 完全一致 (text_* fixture 15 件) |
| host BMP output | oracle と同じ top-down 32bpp、raw と decode 一致 |
| Vector Playground (JS host) | chromium E2E 30/30 + unit 15/15 (M1 相当) |

未実装の機能は黙った no-op にはせず `RadenError::UnsupportedFeature`
として失敗する (see `docs/known-differences.md`)。
