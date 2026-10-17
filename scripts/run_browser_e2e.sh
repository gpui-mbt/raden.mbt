#!/usr/bin/env bash
# run_browser_e2e: Vector Playground の chromium headless E2E。
# site を build し、一時 http サーバを立てて check.mjs を実行する。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/examples/browser"
bash build.sh
cd site
python3 -m http.server 8931 >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
sleep 1
cd ../e2e
node check.mjs http://localhost:8931
node unit.mjs
