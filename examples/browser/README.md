# examples/browser — Vector Playground

MoonBit JS ビルドの描画コアをブラウザで実行し、Rust oracle の
固定参照画像と canonical バイト列で比較する static サイト。

描画計算はすべて MoonBit 側 (`ffi.mbt` / `custom.mbt` → `examples/scenes`) が
担当し、`site/` の JS は DOM・canvas 転送・ハッシュ比較だけを行う薄い host。
Canvas の path/gradient API は使わない。

固定 preset は Rust oracle の参照画像と raw 比較し、`custom` preset は
Path 制御点・fill rule・matrix・clip・paint・stroke・comp op・edge overlay を
編集して MoonBit で live 描画する (参照なしは NO REFERENCE と表示)。

## 構成

- `ffi.mbt` / `moon.pkg`: JS export 層 (ESM)。`render_scene_rgba8` / `render_custom_rgba8`
- `custom.mbt`: M2/M3 custom scene (path/fill rule/matrix/clip/paint/stroke/comp op/overlay)
- `site/index.html` + `site/app.js`: UI。preset/reset/redraw/download/zoom/checker、
  custom 制御点 drag と編集パネル
- `site/core.js`: DOM 非依存の純粋ロジック (hash・byte 比較・alpha 変換・座標変換)
- `site/reference/`: oracle 出力 .raw (build.sh で生成)
- `site/manifest.json`: (scene, 寸法, frame) → {file, sha256} の台帳
- `e2e/check.mjs`: Chromium headless での E2E 検証 (固定 preset / 故障注入)
- `e2e/custom.mjs`: custom scene の fill rule/matrix/clip/stroke/gradient/comp op/overlay/drag
- `e2e/unit.mjs`: core.js の node 直接検証

## ビルドと配信

```sh
./examples/browser/build.sh        # JS bundle + reference + manifest を site/ へ生成
cd examples/browser/site && python3 -m http.server 8931
# http://localhost:8931/ を開く
```

`build.sh` は `moon build --target js examples/browser` の出力と
`conformance/reference/*.raw` を集めて配置する。参照 sha256 は生成時に
再計算して manifest に記録する。

## E2E 検証

```sh
cd examples/browser/e2e
npm install            # playwright のみ
npx playwright install chromium
python3 -m http.server 8931 -d ../site &
node unit.mjs          # core.js 純粋ロジック (alpha 端点・hash・query)
node check.mjs         # 固定 preset のブラウザ E2E (root 配信)
node custom.mjs        # custom scene の編集 E2E
node check.mjs http://localhost:8932/sub   # サブパス配信でも可
```

`scripts/run_browser_e2e.sh` は site build・一時サーバ・3 本のテストを
まとめて実行する。

## 比較の仕様

- 表示用に premultiplied → straight alpha 変換を行うが、
  比較は変換前の canonical バイト列同士で行う (canvas 読み戻しはしない)
- verdict は PASS / FAIL / NO REFERENCE / REF MISSING / RENDER ERROR の
  5 状態。参照が (scene, 寸法, frame) に一致しない場合は比較しない
- 非同期結果は request seq で stale 判定して破棄する
- 入力状態は URL query (?preset=..&w=..) で復元・共有可能。
  custom は `p=x0,y0,...` で制御点も復元する
- custom の編集点は JS overlay canvas に描き、MoonBit の描画 bytes には含めない

## 注意

- 左ペインは RADEN-0002/0008 で生成した Rust oracle の固定画像。
  ブラウザ内で Rust を実行しているわけではない
- デプロイ・公開は未実施。ローカル検証済みの static 資産のみ
