#!/usr/bin/env bash
# run_bench: Rust oracle と MoonBit candidate の描画性能を同一 fixture で比較する。
#
#   conformance/run_bench.sh [frames]
#
# 同じ fixture/seed/frame/size を両実装で実行し、cold start と warm render を
# 分離した raden.bench.v1 レポートを conformance/bench/ へ書き出す。
# 画素 hash も記録する (性能改善が描画結果を変えていないかの検査に使う)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FIXTURES="conformance/bench/fixtures"
FONTS="conformance/fonts"
OUT="conformance/bench"
FRAMES="${1:-30}"
ORACLE_BIN="conformance/rust-oracle/target/release/raden-oracle"

echo "== building oracle (release) =="
(cd conformance/rust-oracle && cargo build --release --locked)

echo "== building moonbit candidate (release native) =="
moon build conformance/moonbit-candidate --target native --release

CANDIDATE_BIN="_build/native/release/build/conformance/moonbit-candidate/moonbit-candidate.exe"
if [ ! -x "$CANDIDATE_BIN" ]; then
  CANDIDATE_BIN="_build/native/release/build/conformance/moonbit-candidate/moonbit-candidate"
fi

export RADEN_CANDIDATE_TOOLCHAIN="$(moonc -v 2>&1 | head -1)"
export RADEN_CANDIDATE_TARGET="native $(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]') release"

mkdir -p "$OUT"

echo "== oracle bench (frames=$FRAMES) =="
"$ORACLE_BIN" bench --fixtures "$FIXTURES" --fonts "$FONTS" \
  --frames "$FRAMES" --out "$OUT/oracle_bench.json"

echo "== moonbit candidate bench (frames=$FRAMES) =="
"$CANDIDATE_BIN" bench --fixtures "$FIXTURES" --fonts "$FONTS" \
  --frames "$FRAMES" --out "$OUT/candidate_bench.json"

echo "== merging report =="
python3 - "$OUT/oracle_bench.json" "$OUT/candidate_bench.json" "$OUT/report.json" <<'PY'
import json, sys

oracle = json.load(open(sys.argv[1]))
cand = json.load(open(sys.argv[2]))
cand_by_id = {r["fixture_id"]: r for r in cand["results"]}
rows = []
mismatch = []
for o in oracle["results"]:
    c = cand_by_id.get(o["fixture_id"])
    row = {
        "fixture_id": o["fixture_id"],
        "oracle": {
            "cold_ms": o["cold_ms"],
            "warm_p50_ms": o["warm_p50_ms"],
            "warm_p95_ms": o["warm_p95_ms"],
            "sha256": o["output_sha256"],
        },
    }
    if c:
        row["candidate"] = {
            "cold_ms": c["cold_ms"],
            "warm_p50_ms": c["warm_p50_ms"],
            "warm_p95_ms": c["warm_p95_ms"],
            "sha256": c["output_sha256"],
        }
        row["p50_ratio"] = c["warm_p50_ms"] / o["warm_p50_ms"] if o["warm_p50_ms"] else None
        row["hash_match"] = c["output_sha256"] == o["output_sha256"]
        if not row["hash_match"]:
            mismatch.append(o["fixture_id"])
    else:
        row["candidate"] = None
        row["hash_match"] = None
        mismatch.append(o["fixture_id"] + " (missing)")
    rows.append(row)

report = {
    "schema": "raden.bench-report.v1",
    "upstream_sha": oracle["upstream_sha"],
    "oracle_toolchain": oracle["toolchain"],
    "candidate_toolchain": cand["toolchain"],
    "build_target": {"oracle": oracle["build_target"], "candidate": cand["build_target"]},
    "results": rows,
    "hash_mismatches": mismatch,
    # 画素一致しない計測結果は比較として成立しないため gate 条件に含める
    "gate": "pass" if not mismatch else "fail",
}
json.dump(report, open(sys.argv[3], "w"), indent=2)
print(f"bench report: gate={report['gate']} ({len(rows)} fixtures)")
for r in rows:
    ratio = r.get("p50_ratio")
    ratio_s = f"{ratio:.2f}x" if ratio is not None else "n/a"
    print(f"  {r['fixture_id']}: oracle_p50={r['oracle']['warm_p50_ms']:.2f}ms "
          f"candidate_p50={(r['candidate'] or {}).get('warm_p50_ms', 0):.2f}ms ratio={ratio_s}")
if mismatch:
    print(f"hash mismatches: {mismatch}")
    sys.exit(1)
PY
