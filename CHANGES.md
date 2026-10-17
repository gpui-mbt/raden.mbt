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
