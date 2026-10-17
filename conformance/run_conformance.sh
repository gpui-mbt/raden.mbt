#!/usr/bin/env bash
# run_conformance: conformance の共通実行入口。
#
#   1. oracle 参照出力 (conformance/reference) が無ければ Rust oracle で生成する。
#   2. MoonBit candidate をビルドし、fixture を実行して conformance/candidate へ出力する。
#   3. Rust comparator で expected.json の全 fixture を照合する (fail-closed)。
#
# 使い方:
#   conformance/run_conformance.sh                 # 全工程
#   conformance/run_conformance.sh --regen-oracle  # oracle 参照も再生成する
#
# 終了コード: comparator のゲートが pass なら 0、fail/error なら非ゼロ。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FIXTURES="conformance/fixtures"
REFERENCE="conformance/reference"
CANDIDATE="conformance/candidate"
EXPECTED="conformance/expected.json"
REPORT="conformance/report.json"
ORACLE_BIN="conformance/rust-oracle/target/release/raden-oracle"

REGEN_ORACLE=0
if [ "${1:-}" = "--regen-oracle" ]; then
  REGEN_ORACLE=1
fi

# 1. oracle 参照出力の生成 (固定 SHA の Rust 実装が実際に上流 API を呼ぶ)。
if [ "$REGEN_ORACLE" = "1" ] || [ ! -d "$REFERENCE" ]; then
  echo "== generating oracle reference outputs =="
  (cd conformance/rust-oracle && cargo build --release --locked)
  "$ORACLE_BIN" generate --fixtures "$FIXTURES" --out "$REFERENCE" --fonts "conformance/fonts"
fi

# 2. oracle 自体の健全性 (負の対照) は cargo test/selftest 側で担保する。
#    ここでは compare が fail-closed で動くことを前提に candidate を生成する。
echo "== building moonbit candidate =="
moon build conformance/moonbit-candidate --target native

CANDIDATE_BIN="_build/native/debug/build/conformance/moonbit-candidate/moonbit-candidate.exe"
export RADEN_CANDIDATE_TOOLCHAIN="$(moonc -v 2>&1 | head -1)"
export RADEN_CANDIDATE_TARGET="native $(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')"

echo "== running moonbit candidate =="
rm -rf "$CANDIDATE"
"$CANDIDATE_BIN" generate --fixtures "$FIXTURES" --out "$CANDIDATE" --fonts "conformance/fonts"

# 3. 比較 (manifest の期待集合と実行結果集合を fail-closed で照合)。
echo "== comparing candidate vs oracle =="
"$ORACLE_BIN" compare \
  --manifest "$EXPECTED" \
  --fixtures "$FIXTURES" \
  --oracle "$REFERENCE" \
  --candidate "$CANDIDATE" \
  --report "$REPORT"
