#!/usr/bin/env bash
# examples/browser/site を static 配信可能な状態にする。
# - MoonBit JS bundle (raden-browser.js) を再生成して配置
# - conformance/reference の scene 出力を reference/ へ複製
# - manifest.json を oracle meta から生成 (sha256 は再計算して台帳化)
set -euo pipefail
cd "$(dirname "$0")/../.."

SITE=examples/browser/site
BUNDLE=_build/js/debug/build/examples/browser/browser.js

moon build --target js examples/browser
cp "$BUNDLE" "$SITE/raden-browser.js"
mkdir -p "$SITE/reference"

python3 - <<'PYEOF'
import json, hashlib, os, shutil

site = "examples/browser/site"
refs = {
    # scene name -> [(fixture_id, frame)]
    "basic_drawing": [("scene_basic_drawing", 0)],
    "gradient_drawing": [("scene_gradient_drawing", 0)],
    "stroke_drawing": [("scene_stroke_drawing", 0)],
    "blit_clip_pattern_paths": [("scene_blit_clip_pattern", 0)],
    "animation": [
        ("scene_animation_f0", 0),
        ("scene_animation_f30", 30),
        ("scene_animation_f90_small", 90),
    ],
}

manifest = {
    "schema": "raden.playground.v1",
    "generated_from": "conformance/reference (rust oracle)",
    "examples": {},
}
for name, fixtures in refs.items():
    entries = []
    for fid, frame in fixtures:
        fx = json.load(open(f"conformance/fixtures/{fid}.json"))
        raw_path = f"conformance/reference/{fid}.raw"
        data = open(raw_path, "rb").read()
        sha = hashlib.sha256(data).hexdigest()
        dst = f"{name}_{fx['width']}x{fx['height']}_f{frame}.raw"
        shutil.copyfile(raw_path, os.path.join(site, "reference", dst))
        entries.append({
            "file": dst,
            "width": fx["width"],
            "height": fx["height"],
            "frame": frame,
            "sha256": sha,
        })
    manifest["examples"][name] = {"references": entries}

json.dump(manifest, open(f"{site}/manifest.json", "w"), indent=2)
print("manifest written:", len(manifest["examples"]), "examples")
PYEOF
echo "site ready at $SITE/"
