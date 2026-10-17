# Changelog

## Unreleased

### Added

- preview 配布: 対応範囲、target 別検証結果、既知差分を明記した
  `release/manifest.json` を追加 (publish/deploy は未実行)。
- fail-closed な回帰ゲート (`scripts/run_checks.sh` +
  `scripts/check_gate.py`) と fault injection テスト
  (`scripts/test_gate.sh`)。
- Rust oracle / MoonBit candidate の性能比較ベンチ
  (`conformance/run_bench.sh`、raden.bench-report.v1、画素 hash gate 付き)。
- 独立 consumer 導入検証 (`consumer/`、`scripts/run_consumer_test.sh`)。
- 配布 artifact 検査 (`release/inspect_artifact.sh`)。
- font/ パッケージ: TrueType パース、グリフ輪郭変換、
  GSUB Single/Ligature・GPOS Single/Pair (liga/kern/clig)、
  `fill_text` / `stroke_text`。
- conformance `text` fixture op と `shapes` メタデータ厳密比較
  (glyph id / cluster (UTF-8 byte index) / advance / offset)。
- host BMP 出力 (`examples/raden-demo/bmp.mbt`): 上流と同じ top-down
  32bpp BI_BITFIELDS。raw / BMP / meta を同一 Image から生成し、
  `examples/run_examples.sh` が BMP を decode して raw と照合する。
- `font_shaping` example を ready 化 (`raden-demo --font/--text`)。
  conformance fixture と同じ raw hash を出力。
- `examples/manifest.json` に core/native_headless/browser/gpui/
  pixel_parity の host 別 status を追加。

### Fixed

- `moon.mod` の存在しない依存 `moonbitlang/async@0.22.5` を registry 実在の
  `0.22.4` へ修正し、native/js の build/test を再現可能にした。
- Rust oracle の toolchain pin を実際にビルド可能な `1.98.1` へ更新し、
  `selftest` を conformance 実行入口へ組み込んだ。
- `scripts/run_checks.sh` の macOS/BSD 非互換な `date +%s%3N` と
  `timeout` 前提を修正し、examples/consumer/artifact/gate 検査を
  required job へ追加した。
- CI の空 `MOON_HOME` 設定を削除し、examples/consumer/artifact/
  gate fault injection/browser E2E の job を追加した。
