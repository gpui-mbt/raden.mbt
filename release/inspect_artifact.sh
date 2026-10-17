#!/usr/bin/env bash
# inspect_artifact: 配布 artifact の検査 (release manifest の宣言範囲を守る)。
#
#   release/inspect_artifact.sh
#
# 検査項目 (全て fail-closed):
#   1. 公開 artifact に絶対ローカルパス (/home/, /Users/) が混入していない
#   2. 秘密情報らしき文字列 (API key/秘密鍵パターン) がない
#   3. LICENSE / README.md が含まれる
#   4. 開発ツール出力 (_build/.mooncakes/target/node_modules/ci) が混入しない
#   5. runtime 依存が release manifest の宣言集合に収まる
#   6. 公開パッケージの .mbti インターフェースが生成済み
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0
fail() { echo "REJECT: $1"; FAIL=1; }

# 公開 artifact のファイル集合 (開発・比較基盤のディレクトリを除く)。
# font/conformance/examples/scripts はソースとして含めるが、
# ビルド生成物・ダウンロード成果物は除外する。
# 追跡・未追跡を問わず artifact 候補を拾う (git ls-files は未追跡を
# 拾えないため find を正とする)。
collect_artifact() {
  find . -type f \
    -not -path './_build/*' -not -path './.git/*' -not -path './.mooncakes/*' \
    -not -path './node_modules/*' -not -path '*/node_modules/*' \
    -not -path './.cargo-home/*' -not -path './.rustup/*' -not -path './.npm-cache/*' \
    -not -path './conformance/rust-oracle/target/*' \
    -not -path './conformance/reference/*' -not -path './conformance/candidate/*' \
    -not -path './ci/*' -not -path './consumer/moon.work' \
    -not -path './examples/browser/site/raden-browser.js' \
    -not -path './examples/browser/site/manifest.json' \
    -not -path './examples/browser/site/reference/*' \
    -not -name '*.raw' -not -name '*.log'
}

FILES=$(collect_artifact | grep -v -e '^./_build' -e '/_build/' -e '/target/' \
  -e 'node_modules' -e '\.mooncakes' -e '\.cargo-home' -e '\.rustup' \
  -e '\.npm-cache' -e 'conformance/reference/' \
  -e 'conformance/candidate/' -e 'conformance/bench/.*\.json' -e 'ci/' || true)

echo "== artifact file count: $(echo "$FILES" | wc -l) =="

# 1. 絶対ローカルパスの混入検査 (ソース・ドキュメント・設定を対象)
HITS=$(echo "$FILES" | xargs grep -l -E '/home/|/Users/|C:\\\\' 2>/dev/null \
  | grep -v -e 'inspect_artifact.sh' -e 'issues/' -e 'docs/' || true)
[ -z "$HITS" ] || fail "絶対パス混入: $HITS"

# 2. 秘密情報パターン
HITS=$(echo "$FILES" | xargs grep -l -E 'BEGIN [A-Z]+ PRIVATE KEY|AKIA[0-9A-Z]{16}|api[_-]?key.{0,4}=.{0,4}[A-Za-z0-9_-]{20,}' 2>/dev/null || true)
[ -z "$HITS" ] || fail "秘密情報らしき文字列: $HITS"

# 3. LICENSE / README
[ -f LICENSE ] || fail "LICENSE なし"
[ -f README.md ] || fail "README.md なし"

# 4. 開発ツール生成物の混入
HITS=$(echo "$FILES" | grep -E '_build/|\.mooncakes/|node_modules/|/target/' || true)
[ -z "$HITS" ] || fail "開発生成物が artifact に混入: $(echo "$HITS" | head -5)"

# 5. runtime 依存の宣言集合との照合 (moon.mod の import)
python3 - <<'PY' || fail "runtime 依存が manifest 宣言外を含む"
import json, re, sys
mod = open("moon.mod").read()
deps = set(re.findall(r'"([a-zA-Z0-9_/-]+)@[0-9]', mod))
manifest = json.load(open("release/manifest.json"))
allowed = {d["module"] for d in manifest["runtime_dependencies"]}
extra = deps - allowed
if extra:
    print(f"undeclared deps: {extra}")
    sys.exit(1)
print(f"runtime deps ok: {sorted(deps)}")
PY

# 6. 公開パッケージの .mbti
for d in . font internal/pixel internal/raster examples/scenes; do
  [ -f "$d/pkg.generated.mbti" ] || fail "$d/pkg.generated.mbti なし (moon info 未実行)"
done

# 7. font テストが fs を wbtest に限定しているか (pure core の検査)
grep -q 'for "wbtest"' font/moon.pkg || fail "font/moon.pkg の async/fs が wbtest 限定でない"

if [ "$FAIL" = "1" ]; then
  echo "artifact inspection: REJECTED"
  exit 1
fi
echo "artifact inspection: ok ($(echo "$FILES" | wc -l) files)"
