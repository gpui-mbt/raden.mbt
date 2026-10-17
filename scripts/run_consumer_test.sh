#!/usr/bin/env bash
# run_consumer_test: 独立 consumer から公開 library を導入して描画する検証。
#
#   scripts/run_consumer_test.sh
#
# consumer/ は別 moon module で、非公開 helper やローカル依存なしに
# gpui-mbt/raden の公開 API だけを使う。moon work workspace で
# リポジトリを dep として解決し、native / js の両 target で
# basic drawing を実行する (publish は行わない)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/consumer"

# workspace manifest は実行時に生成する (環境依存の絶対パスを含むため
# リポジトリへはコミットしない)。
rm -f moon.work
moon work init >/dev/null
moon work use . .. >/dev/null

echo "== consumer run: native =="
moon run consumer --target native

echo "== consumer run: js =="
moon run consumer --target js

echo "consumer test: ok"
