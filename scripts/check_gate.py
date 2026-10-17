#!/usr/bin/env python3
"""check_gate: ci/jobs/*.json を fail-closed に集約してゲート判定する。

使い方:
    python3 scripts/check_gate.py <jobs_dir> <report_out.json>

判定規則:
  - required job が結果ファイルごと欠落 → missing → gate fail
  - required job の status が pass 以外 (fail/error/cancelled/skipped) → gate fail
  - optional job が fail/error/cancelled → gate fail (skipped は許容)
  - 上記以外 → gate pass

集約された結果集合だけを見て判定する。job 側の終了コードを信用せず、
書き出された status のみを信頼する (fail-closed)。
"""

import json
import sys
from pathlib import Path

REQUIRED_JOBS = [
    "moon_fmt_check",
    "moon_check_native",
    "moon_check_js",
    "moon_test_native",
    "moon_test_js",
    "conformance",
    "examples",
    "consumer",
    "artifact",
    "gate_fault_injection",
]

VALID_STATUSES = {"pass", "fail", "error", "skipped", "cancelled"}


def main() -> int:
    jobs_dir = Path(sys.argv[1])
    report_path = Path(sys.argv[2])

    jobs = {}
    for p in sorted(jobs_dir.glob("*.json")):
        jobs[p.stem] = json.loads(p.read_text())

    failures = []
    for name in REQUIRED_JOBS:
        job = jobs.get(name)
        if job is None:
            failures.append(f"{name}: missing (required job の結果なし)")
            continue
        status = job.get("status")
        if status not in VALID_STATUSES:
            failures.append(f"{name}: invalid status {status!r}")
        elif status != "pass":
            failures.append(f"{name}: {status} (required job が pass でない)")

    for name, job in jobs.items():
        if name in REQUIRED_JOBS:
            continue
        status = job.get("status")
        if status in {"fail", "error", "cancelled"}:
            failures.append(f"{name}: {status} (optional job の失敗)")
        elif status not in VALID_STATUSES:
            failures.append(f"{name}: invalid status {status!r}")

    report = {
        "schema": "raden.ci-report.v1",
        "required_jobs": REQUIRED_JOBS,
        "jobs": jobs,
        "failures": failures,
        "gate": "pass" if not failures else "fail",
    }
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")

    summary = ", ".join(f"{n}={j.get('status')}" for n, j in jobs.items())
    print(f"gate: {report['gate']} ({summary})")
    for f in failures:
        print(f"  reject: {f}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
