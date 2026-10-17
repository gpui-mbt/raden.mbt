#!/usr/bin/env bash
# examples/manifest.json の全 example を照合する検証スクリプト。
# - ready: raden-demo で canonical サイズを生成し、manifest の sha256 と比較。
#          BMP を decode し、寸法・channel 順・raw との一致を確認する。
# - blocked: raden-demo が非 0 で失敗することを確認
# 使い方: examples/run_examples.sh [--work <dir>]
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="/tmp/raden-examples"
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --work)
      WORK="${2:?--work requires a directory}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

DEMO="./_build/native/debug/build/examples/raden-demo/raden-demo.exe"
if [ ! -x "$DEMO" ]; then
  DEMO="./_build/native/debug/build/examples/raden-demo/raden-demo"
fi

if [ ! -x "$DEMO" ]; then
  echo "raden-demo not built. run: moon build examples/raden-demo" >&2
  exit 1
fi
mkdir -p "$WORK"
export RADEN_EXAMPLES_WORK="$WORK"
export RADEN_EXAMPLES_DEMO="$DEMO"

python3 - <<'EOF'
import json, hashlib, os, struct, subprocess, sys

manifest = json.load(open("examples/manifest.json"))
work = os.environ.get("RADEN_EXAMPLES_WORK", "/tmp/raden-examples")
demo = os.environ.get("RADEN_EXAMPLES_DEMO", "./_build/native/debug/build/examples/raden-demo/raden-demo.exe")
font = "conformance/fonts/SourceSans3-Regular.ttf"
fails = []

def run(args):
    return subprocess.run(args, capture_output=True, text=True)

def decode_bmp(path):
    """top-down 32bpp BI_BITFIELDS を検証し、(w, h, BGRA bytes) を返す。"""
    data = open(path, "rb").read()
    if len(data) < 66:
        raise ValueError("too short")
    if data[0:2] != b"BM":
        raise ValueError("not BM")
    file_size, = struct.unpack_from("<I", data, 2)
    offset, = struct.unpack_from("<I", data, 10)
    dib, = struct.unpack_from("<I", data, 14)
    w, h, planes, bpp = struct.unpack_from("<iiHH", data, 18)
    comp, image_size = struct.unpack_from("<II", data, 30)
    rmask, gmask, bmask = struct.unpack_from("<III", data, 54)
    if file_size != len(data):
        raise ValueError(f"file size {file_size} != {len(data)}")
    if dib != 40 or planes != 1 or bpp != 32 or comp != 3:
        raise ValueError(f"header dib={dib} planes={planes} bpp={bpp} comp={comp}")
    if h >= 0:
        raise ValueError(f"expected top-down negative height, got {h}")
    if (rmask, gmask, bmask) != (0x00FF0000, 0x0000FF00, 0x000000FF):
        raise ValueError(f"masks {rmask:#x},{gmask:#x},{bmask:#x}")
    if offset != 66:
        raise ValueError(f"offset {offset} != 66")
    if image_size != w * (-h) * 4:
        raise ValueError("image size mismatch")
    pixels = data[offset:]
    if len(pixels) != w * (-h) * 4:
        raise ValueError("pixel data length mismatch")
    return w, -h, pixels

for entry in manifest["examples"]:
    name = entry["name"]
    status = entry["status"]
    parity = entry.get("pixel_parity")
    if status == "ready":
        if parity != "pass":
            fails.append((name, f"ready but pixel_parity={parity}"))
            continue
        w, h = entry["canonical_size"]
        args = [demo, "--example", name, "--output", work, "--headless"]
        if name in ("font_shaping", "raden_player"):
            args += ["--font", font]
        if "fps" in entry:
            args += ["--fps", str(entry["fps"])]
        r = run(args)
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
        # meta と raw/BMP の hash を照合
        meta = json.load(open(os.path.join(work, name + ".meta.json")))
        if meta.get("sha256") != got or meta.get("width") != w or meta.get("height") != h:
            fails.append((name, "meta does not match raw/size"))
            continue
        # BMP を decode して raw (RGBA) と channel 順を比較
        try:
            bw, bh, bgra = decode_bmp(os.path.join(work, name + ".bmp"))
        except Exception as e:
            fails.append((name, f"bmp decode failed: {e}"))
            continue
        if (bw, bh) != (w, h):
            fails.append((name, f"bmp size {bw}x{bh} != {w}x{h}"))
            continue
        if len(bgra) != len(raw):
            fails.append((name, "bmp/raw length mismatch"))
            continue
        bad = None
        for i in range(0, len(raw), 4):
            if (bgra[i] != raw[i + 2] or bgra[i + 1] != raw[i + 1]
                    or bgra[i + 2] != raw[i] or bgra[i + 3] != raw[i + 3]):
                bad = i
                break
        if bad is not None:
            fails.append((name, f"bmp channel mismatch at byte {bad}"))
            continue
        print(f"{name}: ok (raw {got[:16]}..., bmp {len(bgra)} bytes)")
    elif status == "blocked":
        if parity == "pass":
            fails.append((name, "blocked but pixel_parity=pass"))
            continue
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
