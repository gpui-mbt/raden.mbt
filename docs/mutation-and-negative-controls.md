# 負の対照・mutation 評価記録

RADEN-0012 の「正常/不正入力 corpus、負の対照、mutation の評価記録」に対応。
mutation スコアを目標にはせず、検出手段の網羅性を記録する。

## 負の対照 (現行の検出手段)

| 変異クラス | 検出手段 | 状態 |
| --- | --- | --- |
| pixel 1 ドット差 | conformance raw bytes 完全一致比較 | fail-closed |
| 比較器自身の偽陽性 | `raden-oracle selftest` (13 control: 色/1画素/alpha/全黒/サイズ/旧 hash/非ゼロ exit/欠落/改ざん/空集合) | 13/13 拒否 |
| shape 結果の差 (glyph id/cluster/advance/offset) | meta `shapes` 厳密比較 → `shape_mismatch` | 実測済み (改竄で gate fail) |
| fixture 改竄・hash 陳腐化 | input_sha256 再計算照合 → `stale_input` | fail-closed |
| oracle 参照の陳腐化 | `upstream_sha` 照合 → `stale_oracle` | fail-closed |
| fixture 欠落/重複/空集合 | expected manifest 集合照合 | fail-closed |
| 破損フォント入力 | font/corrupt_wbtest (26 native / 11 js 件) | 全件明示拒否 |
| BMP の channel/寸法差 | examples/run_examples.sh が decode して raw と比較 | fail-closed |
| blocked example の暗黙成功 | examples/run_examples.sh が非 0 exit を要求 | fail-closed |
| CI job missing/fail/cancelled/skip | scripts/test_gate.sh (8 ケース) | 全件拒否確認済み |
| browser の参照欠落/旧 SHA/寸法違い/順序逆転 | chromium E2E の故障注入 | 30/30 pass |
| custom scene の編集 (fill rule/matrix/clip/stroke/gradient/comp op/overlay/drag) | `e2e/custom.mjs` | 17/17 pass |
| 配布物混入 (絶対パス/秘密情報/生成物) | release/inspect_artifact.sh | 実行済み |
| bench の画素差 | run_bench.sh の hash_match gate | fail-closed |

## mutation survivor の分類方針

現時点で体系的 mutation ツール実行は未実施。負の対照で
「画素差を出す変異」「構造差を出す変異」「メタデータ変異」
「プロセス/集合変異」の 4 クラスを fixture 層で捕捉している。
survivor が出た場合は equivalent (例: 未到達分支、デバッグ専用コード)
か fixture 追加要かを分類し、非 equivalent は fixture へ落とす。
