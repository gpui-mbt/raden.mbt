#!/usr/bin/env bash
# examples/manifest.json の全 example を照合する検証スクリプト。
# - ready: raden-demo で canonical サイズを生成し、manifest の sha256 と比較
# - blocked: raden-demo が非 0 で失敗することを確認
# 使い方: examples/run_examples.sh [--work <dir>]
set -u
cd "$(dirname "$0")/.."

WORK="${2:-/tmp/raden-examples}"
DEMO="./_build/native/debug/build/examples/raden-demo/raden-demo.exe"

if [ ! -x "$DEMO" ]; then
  echo "raden-demo not built. run: moon build examples/raden-demo" >&2
  exit 1
fi
mkdir -p "$WORK"

python3 - <<'EOF'
import json, hashlib, os, subprocess, sys

manifest = json.load(open("examples/manifest.json"))
work = os.environ.get("RADEN_EXAMPLES_WORK", "/tmp/raden-examples")
demo = "./_build/native/debug/build/examples/raden-demo/raden-demo.exe"
fails = []

def run(args):
    return subprocess.run(args, capture_output=True, text=True)

for entry in manifest["examples"]:
    name = entry["name"]
    status = entry["status"]
    if status == "ready":
        w, h = entry["canonical_size"]
        r = run([demo, "--example", name, "--output", work, "--headless"])
        if r.returncode != 0:
            fails.append((name, f"exit={r.returncode}: {r.stderr.strip()}"))
            continue
        raw = open(os.path.join(work, name + ".raw"), "rb").read()
        got = hashlib.sha256(raw).hexdigest()
        want = entry["raw_sha256"]
        want = want["frame0_1280x720"] if isinstance(want, dict) else want
        if got != want:
            fails.append((name, f"sha256 mismatch: got {got}, want {want}"))
            continue
        print(f"{name}: ok ({got[:16]}...)")
    elif status == "blocked":
        r = run([demo, "--example", name, "--output", work, "--headless"])
        if r.returncode == 0:
            fails.append((name, "blocked example unexpectedly succeeded"))
            continue
        print(f"{name}: blocked (exit={r.returncode})")
    else:
        fails.append((name, f"unknown status: {status}"))

# manifest の件数が上流 8 本と一致するか
if len(manifest["examples"]) != 8:
    fails.append(("manifest", f"expected 8 examples, got {len(manifest['examples'])}"))

if fails:
    for name, why in fails:
        print(f"FAIL {name}: {why}", file=sys.stderr)
    sys.exit(1)
print("all examples verified")
EOF
