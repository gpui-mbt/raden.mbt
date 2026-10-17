#!/usr/bin/env bash
# test_gate: check_gate.py の fault injection テスト。
#
# required job の missing / fail / cancelled / skipped / invalid status と
# optional job の fail がそれぞれ gate を拒否すること、
# 全 pass + optional skipped が gate を通すことを検証する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkjobs() {
  local dir="$1"; mkdir -p "$dir"
  for j in moon_fmt_check moon_check_native moon_check_js moon_test_native moon_test_js conformance examples consumer artifact gate_fault_injection; do
    printf '{"name":"%s","required":true,"status":"pass","duration_ms":1,"command":"x","note":""}\n' "$j" > "$dir/$j.json"
  done
}

expect_fail() {
  local desc="$1" dir="$2"
  if python3 scripts/check_gate.py "$dir" "$dir/report.json" >/dev/null; then
    echo "FAIL: $desc — gate が通った (拒否すべき)" >&2
    exit 1
  fi
  echo "ok: $desc → gate fail (期待通り拒否)"
}

expect_pass() {
  local desc="$1" dir="$2"
  if ! python3 scripts/check_gate.py "$dir" "$dir/report.json" >/dev/null; then
    echo "FAIL: $desc — gate が拒否した" >&2
    exit 1
  fi
  echo "ok: $desc → gate pass"
}

# 1. 全 pass → gate pass
mkjobs "$TMP/all_pass"
expect_pass "全 required pass" "$TMP/all_pass"

# 2. required job の結果欠落 → fail
mkjobs "$TMP/missing"; rm "$TMP/missing/moon_test_js.json"
expect_fail "required job の結果欠落" "$TMP/missing"

# 3. required job fail → fail
mkjobs "$TMP/job_fail"
printf '{"name":"conformance","required":true,"status":"fail","duration_ms":1,"command":"x","note":""}\n' > "$TMP/job_fail/conformance.json"
expect_fail "required job fail" "$TMP/job_fail"

# 4. required job cancelled (timeout) → fail
mkjobs "$TMP/job_cancelled"
printf '{"name":"moon_test_native","required":true,"status":"cancelled","duration_ms":1,"command":"x","note":""}\n' > "$TMP/job_cancelled/moon_test_native.json"
expect_fail "required job cancelled" "$TMP/job_cancelled"

# 5. required job skipped → fail (skip は成功としない)
mkjobs "$TMP/job_skipped"
printf '{"name":"moon_check_js","required":true,"status":"skipped","duration_ms":0,"command":"x","note":""}\n' > "$TMP/job_skipped/moon_check_js.json"
expect_fail "required job skipped" "$TMP/job_skipped"

# 6. 不正 status → fail
mkjobs "$TMP/job_invalid"
printf '{"name":"conformance","required":true,"status":"success","duration_ms":1,"command":"x","note":""}\n' > "$TMP/job_invalid/conformance.json"
expect_fail "required job 不正 status" "$TMP/job_invalid"

# 7. optional job fail → fail (optional でも実行して失敗したら拒否)
mkjobs "$TMP/opt_fail"
printf '{"name":"bench","required":false,"status":"fail","duration_ms":1,"command":"x","note":""}\n' > "$TMP/opt_fail/bench.json"
expect_fail "optional job fail" "$TMP/opt_fail"

# 8. optional job skipped → pass (環境不足の未実行は許容)
mkjobs "$TMP/opt_skip"
printf '{"name":"browser_e2e","required":false,"status":"skipped","duration_ms":0,"command":"x","note":"playwright 未導入"}\n' > "$TMP/opt_skip/browser_e2e.json"
expect_pass "optional job skipped" "$TMP/opt_skip"

echo "gate fault-injection: all checks passed"
