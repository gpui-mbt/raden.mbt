# examples — 上流 example のヘッドレス再現

上流 `shiguredo/raden` の example 8 本を、描画 scene (`examples/scenes`) と
表示/ファイル host (`examples/raden-demo`, `examples/browser`) に分離して
追跡する。scene は壁時計・乱数・ファイルパスに依存せず、frame/fps を
明示的に受け取る。

## 状態

| example | core | native_headless | browser | gpui | pixel_parity |
| --- | --- | --- | --- | --- | --- |
| basic_drawing | ready | ready | ready | blocked | pass |
| gradient_drawing | ready | ready | ready | blocked | pass |
| stroke_drawing | ready | ready | ready | blocked | pass |
| blit_clip_pattern_paths | ready | ready | ready | blocked | pass |
| animation | ready | ready | ready | blocked | pass |
| font_shaping | ready | ready | not_implemented | blocked | pass |
| tiger | blocked (asset provenance) | blocked | blocked | blocked | not_verified |
| raden_player | blocked (raw_player host) | blocked | n/a | blocked | not_verified |

`gpui` は RADEN-0010 が gpui@0.7.2 の画像 upload API 不在で blocked。
`browser` は `examples/browser` の M1 (固定参照比較) のみ。

## Native headless

```sh
moon build examples/raden-demo

DEMO=_build/native/debug/build/examples/raden-demo/raden-demo.exe
$DEMO --example basic_drawing --output /tmp/demo --headless
# => /tmp/demo/basic_drawing.raw       canonical premultiplied RGBA8
# => /tmp/demo/basic_drawing.bmp       top-down 32bpp BI_BITFIELDS
# => /tmp/demo/basic_drawing.meta.json sha256 / 寸法 / frame / bmp hash

# animation は t = frame / fps (実時間不使用)
$DEMO --example animation --frame 30 --fps 60 --output /tmp/demo

# font_shaping は固定フォントを読み、conformance fixture と同じ scene を描く
$DEMO --example font_shaping \
  --font conformance/fonts/SourceSans3-Regular.ttf --output /tmp/demo
```

`blocked` の example は非 0 で終了し、`reason` と `remediation` を表示する。
空画像や成功 exit でごまかさない。

## 全件検証

```sh
examples/run_examples.sh [--work <dir>]
```

`ready` は manifest の canonical raw sha256 と BMP decode (寸法・channel 順・
raw との一致) を検証し、`blocked` は非 0 exit を要求する。manifest は
`core / native_headless / browser / gpui / pixel_parity` を個別 status で持ち、
`pixel_parity: pass` は oracle raw 完全一致を意味する。

## 参照画像

browser の参照は Rust oracle の生成物 (`conformance/reference`) から作る。
`examples/browser/build.sh` は `conformance/run_conformance.sh` の後、
または `--regen-oracle` で reference を生成した後に実行する。
