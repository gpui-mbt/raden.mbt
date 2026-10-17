# 負の対照・mutation 評価記録

RADEN-0012 の「正常/不正入力 corpus、負の対照、mutation の評価記録」に対応。
mutation スコアを目標にはせず、検出手段の網羅性を記録する。

## 負の対照 (現行の検出手段)

| 変異クラス | 検出手段 | 状態 |
| --- | --- | --- |
| pixel 1 ドット差 | conformance raw bytes 完全一致比較 | fail-closed |
| shape 結果の差 (glyph id/cluster/advance/offset) | meta `shapes` 厳密比較 → `shape_mismatch` | 実測済み (改竄で gate fail) |
| fixture 改竄・hash 陳腐化 | input_sha256 再計算照合 → `stale_input` | fail-closed |
| oracle 参照の陈旧化 | `upstream_sha` 照合 → `stale_oracle` | fail-closed |
| fixture 欠落/重複/空集合 | expected manifest 集合照合 | fail-closed |
| 破損フォント入力 | font/corrupt_wbtest (26 native / 11 js 件) | 全件明示拒否 |
| CI job missing/fail/cancelled/skip | scripts/test_gate.sh (8 ケース) | 全件拒否確認済み |
| 配布物混入 (絶対パス/秘密情報/生成物) | release/inspect_artifact.sh | 実行済み |
| bench の画素差 | run_bench.sh の hash_match gate | fail-closed |

## mutation survivor の分類方針

現時点で体系的 mutation ツール実行は未実施。負の対照で
「画素差を出す変異」「構造差を出す変異」「メタデータ変異」
「プロセス/集合変異」の 4 クラスを fixture 層で捕捉している。
survivor が出た場合は equivalent (例: 未到達分支、デバッグ専用コード)
か fixture 追加要かを分類し、非 equivalent は fixture へ落とす。
