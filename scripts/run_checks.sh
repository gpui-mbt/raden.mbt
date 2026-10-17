#!/usr/bin/env bash
# run_checks: 回帰ゲートの実行入口。
#
#   scripts/run_checks.sh              # 全 required job + 環境が揃った optional job
#   scripts/run_checks.sh --with-bench # 性能ベンチ (optional) も実行
#
# 各 job の結果を ci/jobs/<name>.json に書き、ci/report.json へ集約する。
# 判定は scripts/check_gate.py が行う (fail-closed: required job の
# missing/fail/error/cancelled/skipped は全て gate fail)。
#
# optional job は「実行環境があって失敗」なら gate fail、
# 「環境不足で未実行 (skipped)」なら gate 対象外とする。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CI_DIR="ci"
JOBS_DIR="$CI_DIR/jobs"
LOGS_DIR="$CI_DIR/logs"
mkdir -p "$JOBS_DIR" "$LOGS_DIR"
rm -f "$JOBS_DIR"/*.json

WITH_BENCH=0
[ "${1:-}" = "--with-bench" ] && WITH_BENCH=1

# job 結果を ci/jobs/<name>.json に記録する。
# status: pass | fail | error | skipped | cancelled
write_job() {
  python3 - "$JOBS_DIR/$1.json" "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json, sys
path, name, required, status, duration, command, note = sys.argv[1:8]
json.dump({
    "name": name,
    "required": required == "true",
    "status": status,
    "duration_ms": int(duration),
    "command": command,
    "note": note,
}, open(path, "w"), indent=2)
PY
}

run_job() {
  local name="$1" required="$2"; shift 2
  local log="$LOGS_DIR/$name.log"
  echo "== job: $name ==" | tee "$log"
  local t0 t1 rc status
  t0=$(date +%s%3N)
  timeout "${RADEN_JOB_TIMEOUT:-600}" "$@" >>"$log" 2>&1
  rc=$?
  t1=$(date +%s%3N)
  case $rc in
    0) status=pass ;;
    124|137) status=cancelled ;;
    *) status=fail ;;
  esac
  write_job "$name" "$required" "$status" "$((t1 - t0))" "$*"
  echo "   -> $status ($((t1-t0))ms, log: $log)"
  return 0
}

run_optional() {
  local name="$1" missing_reason="$2"; shift 2
  if [ -n "$missing_reason" ]; then
    write_job "$name" false skipped 0 "$*" "$missing_reason"
    echo "== job: $name == skipped ($missing_reason)"
    return 0
  fi
  run_job "$name" false "$@"
}

# --- required jobs ---
run_job moon_fmt_check true moon fmt --check
run_job moon_check_native true moon check --target native
run_job moon_check_js true moon check --target js
run_job moon_test_native true moon test --target native
run_job moon_test_js true moon test --target js
run_job conformance true bash conformance/run_conformance.sh

# --- optional jobs ---
BENCH_REASON=""
[ "$WITH_BENCH" = "1" ] || BENCH_REASON="--with-bench 未指定"
run_optional bench "$BENCH_REASON" bash conformance/run_bench.sh 30

E2E_REASON=""
if [ ! -d "examples/browser/e2e/node_modules/playwright" ]; then
  E2E_REASON="playwright 未導入 (examples/browser/e2e)"
fi
if [ -z "$E2E_REASON" ]; then
  run_optional browser_e2e "" bash scripts/run_browser_e2e.sh
else
  run_optional browser_e2e "$E2E_REASON" true
fi

# 集約 + ゲート判定
python3 scripts/check_gate.py "$JOBS_DIR" "$CI_DIR/report.json"
