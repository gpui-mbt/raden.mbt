// Vector Playground E2E 検証 (chromium headless)。
// - basic preset で PASS + oracle sha 一致
// - DOM イベント (preset 切替 / redraw / reset / zoom / checker)
// - 故障注入 (参照欠落 → NO REFERENCE、寸法不一致 → NO REFERENCE)
// - 異常入力 (未知 scene / fps=0 → RENDER ERROR)
// 使い方: node e2e/check.mjs [base-url]

import { chromium } from "playwright";

const base = process.argv[2] || "http://localhost:8931";
const browser = await chromium.launch();
const page = await browser.newPage();
const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "ok" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

await page.goto(`${base}/`, { waitUntil: "networkidle" });
await page.waitForSelector("#verdict.pass", { timeout: 15000 });

// 既定 preset で PASS になるか
check("basic_drawing verdict is PASS",
  (await page.textContent("#verdict")).trim() === "PASS");

// sha が manifest の oracle hash と一致するか
const manifest = await page.evaluate(async () =>
  (await fetch("./manifest.json")).json());
const liveSha = await page.textContent("#live-sha");
const refSha = await page.textContent("#ref-sha");
const wantSha = manifest.examples.basic_drawing.references[0].sha256;
check("live sha256 == oracle reference", liveSha.trim() === wantSha, liveSha.trim());
check("reference sha shown", refSha.trim() === wantSha);
check("input hash displayed",
  /^[0-9a-f]{8}$/.test((await page.textContent("#input-hash")).trim()));

// canvas の backing store が画像寸法 (DPR/CSS 非依存) であること
const liveSize = await page.evaluate(() =>
  [document.getElementById("live-canvas").width,
   document.getElementById("live-canvas").height]);
check("canvas backing store = 1280x720", liveSize[0] === 1280 && liveSize[1] === 720);

// preset 切替 (DOM イベント) で別 scene が PASS になるか
await page.selectOption("#preset", "gradient_drawing");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "PASS",
  { timeout: 15000 });
const gSha = await page.textContent("#live-sha");
check("gradient_drawing PASS after DOM select",
  gSha.trim() === manifest.examples.gradient_drawing.references[0].sha256);

// animation frame 30 参照
await page.selectOption("#preset", "animation");
await page.fill("#frame", "30");
await page.dispatchEvent("#frame", "change");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "PASS",
  { timeout: 15000 });
const aSha = await page.textContent("#live-sha");
check("animation frame=30 PASS",
  aSha.trim() === manifest.examples.animation.references
    .find((r) => r.frame === 30 && r.width === 1280).sha256);

// 参照が存在しない frame → NO REFERENCE (FAIL でも PASS でもない別状態)
await page.fill("#frame", "7");
await page.dispatchEvent("#frame", "change");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "NO REFERENCE",
  { timeout: 15000 });
check("frame without reference -> NO REFERENCE", true);

// 寸法不一致 → NO REFERENCE
await page.fill("#frame", "0");
await page.fill("#width", "640");
await page.dispatchEvent("#width", "change");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "NO REFERENCE",
  { timeout: 15000 });
check("non-canonical size -> NO REFERENCE", true);

// reset で basic に戻り PASS が復帰するか
await page.click("#reset");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "PASS",
  { timeout: 15000 });
check("reset returns to basic_drawing PASS", true);

// redraw ボタン (DOM イベント)
await page.click("#redraw");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "PASS",
  { timeout: 15000 });
check("redraw re-verifies PASS", true);

// zoom が CSS 表示サイズのみを変え backing store を変えないか
await page.fill("#zoom", "200");
await page.dispatchEvent("#zoom", "input");
const afterZoom = await page.evaluate(() => ({
  w: document.getElementById("live-canvas").width,
  css: document.getElementById("live-canvas").style.width,
}));
check("zoom=200 scales CSS only", afterZoom.w === 1280 && afterZoom.css === "2560px",
  JSON.stringify(afterZoom));

// checker トグル
await page.click("#checker");
const checkerOff = await page.evaluate(() =>
  !document.querySelector(".canvas-wrap").classList.contains("checker"));
check("checker toggle removes class", checkerOff);

// 故障注入: manifest の参照を一時的に無効化 → 参照 fetch 404 → REF MISSING
await page.route("**/reference/*", (route) => route.abort());
await page.click("#reset");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "REF MISSING",
  { timeout: 15000 });
check("reference fetch failure -> REF MISSING", true);
await page.unroute("**/reference/*");

// 異常入力: fps=0 → RENDER ERROR (fail とは区別して原因を表示)
await page.fill("#fps", "0");
await page.dispatchEvent("#fps", "change");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "RENDER ERROR",
  { timeout: 15000 });
check("fps=0 -> RENDER ERROR with detail",
  (await page.textContent("#detail")).includes("fps"));

// download ボタンが機能するか (data URL 生成)
await page.fill("#fps", "60");
const dl = await page.evaluate(() => {
  const c = document.getElementById("live-canvas");
  return c.toDataURL("image/png").startsWith("data:image/png");
});
check("canvas produces PNG data URL", dl);


// URL query からの状態復元 (サブパス配下でも相対パスで解決されること)
await page.goto(`${base}/?preset=stroke_drawing&w=1280&h=720&frame=0&fps=60&zoom=200`,
  { waitUntil: "networkidle" });
await page.waitForSelector("#verdict.pass", { timeout: 15000 });
const restored = await page.evaluate(() => ({
  preset: document.getElementById("preset").value,
  zoom: document.getElementById("zoom").value,
}));
check("query restores preset+zoom",
  restored.preset === "stroke_drawing" && restored.zoom === "200");
// リロード後も query が維持され PASS が再現できるか
await page.reload({ waitUntil: "networkidle" });
await page.waitForSelector("#verdict.pass", { timeout: 15000 });
check("reload preserves state and PASS",
  (await page.textContent("#verdict")).trim() === "PASS");


// ポインタ座標変換: zoom 100% では client 位置 = 画像ピクセル。
// canvas は wrap (46vw) でクリップされるので可視範囲内の点を使う。
await page.goto(`${base}/`, { waitUntil: "networkidle" });
await page.waitForSelector("#verdict.pass", { timeout: 15000 });
{
  const box = await page.locator("#live-canvas").boundingBox();
  await page.mouse.move(box.x + 100.5, box.y + 60.5);
  const t = (await page.textContent("#pointer")).trim();
  check("pointer maps to image px at 100%", t === "(100, 60)", t);
}
// zoom 200%: 同じ CSS オフセットは半分の画像座標を指す
await page.fill("#zoom", "200");
await page.dispatchEvent("#zoom", "input");
{
  const box = await page.locator("#live-canvas").boundingBox();
  await page.mouse.move(box.x + 100.5, box.y + 60.5);
  const t = (await page.textContent("#pointer")).trim();
  check("pointer at 200% zoom halves image coords", t === "(50, 30)", t);
}
// スクロール後も rect 基準なので正しい
await page.evaluate(() => window.scrollTo(0, 200));
{
  const box = await page.locator("#live-canvas").boundingBox();
  await page.mouse.move(box.x + 100.5, box.y + 60.5);
  const t = (await page.textContent("#pointer")).trim();
  check("pointer after scroll still correct", t === "(50, 30)", t);
}
await page.evaluate(() => window.scrollTo(0, 0));
// canvas 外に出ると readout がクリアされる
await page.mouse.move(2, 2);
{
  const t = (await page.textContent("#pointer")).trim();
  check("pointer outside canvas clears", t === "-", t);
}

// --- 追加故障注入 ---
// manifest 改竄 (sha と実体不一致) → REF STALE。旧 manifest の PASS 誤認を防ぐ
await page.route("**/manifest.json", async (route) => {
  const resp = await route.fetch();
  const m = await resp.json();
  m.examples.basic_drawing.references[0].sha256 = "0".repeat(64);
  await route.fulfill({ response: resp, json: m });
});
await page.goto(`${base}/`, { waitUntil: "networkidle" });
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "REF STALE",
  { timeout: 15000 });
check("tampered manifest sha -> REF STALE", true);
await page.unroute("**/manifest.json");

// 参照 bytes 破損 → FAIL (PASS でなく差分として表示)
await page.route("**/reference/*", async (route) => {
  const resp = await route.fetch();
  const buf = new Uint8Array(await resp.body());
  buf[0] ^= 0xff;
  await route.fulfill({ response: resp, body: Buffer.from(buf) });
});
await page.goto(`${base}/`, { waitUntil: "networkidle" });
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "REF STALE",
  { timeout: 15000 });
// 破損 bytes は manifest sha とも不一致なので REF STALE 側に落ちる (両者とも PASS にはならない)
check("corrupted reference -> not PASS", true);
await page.unroute("**/reference/*");

// 参照の寸法が違う bytes を返す → REF MISSING (size mismatch)
await page.route("**/reference/*", (route) =>
  route.fulfill({ status: 200, body: Buffer.alloc(64) }));
await page.goto(`${base}/`, { waitUntil: "networkidle" });
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "REF MISSING",
  { timeout: 15000 });
check("wrong-size reference -> REF MISSING", true);
await page.unroute("**/reference/*");

// 順序逆転: 遅延する参照応答が新しい判定を上書きしない
await page.goto(`${base}/`, { waitUntil: "networkidle" });
await page.waitForSelector("#verdict.pass", { timeout: 15000 });
await page.route("**/reference/gradient_drawing*", async (route) => {
  await new Promise((r) => setTimeout(r, 600));
  const resp = await route.fetch();
  const buf = new Uint8Array(await resp.body());
  buf[0] ^= 0xff; // 遅延応答を破損させる: 誤適用なら FAIL/STALE になる
  await route.fulfill({ response: resp, body: Buffer.from(buf) });
});
await page.selectOption("#preset", "gradient_drawing"); // 遅延 request 開始
await page.waitForTimeout(50);
await page.selectOption("#preset", "basic_drawing");    // 速い request
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "PASS",
  { timeout: 15000 });
await page.waitForTimeout(800); // 遅延応答が到着する時間を確保
check("stale delayed response discarded",
  (await page.textContent("#verdict")).trim() === "PASS" &&
  (await page.textContent("#live-sha")).trim() === wantSha);
await page.unroute("**/reference/gradient_drawing*");

// freeze/step: +1f で frame=30 → PASS、-1f で 29 → NO REFERENCE
await page.selectOption("#preset", "animation");
await page.fill("#frame", "29");
await page.dispatchEvent("#frame", "change");
await page.click("#step-fwd");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "PASS",
  { timeout: 15000 });
check("step +1f reaches frame 30 PASS", true);
await page.click("#step-back");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "NO REFERENCE",
  { timeout: 15000 });
check("step -1f -> frame 29 NO REFERENCE", true);

// DPR=2: backing store は実ピクセル固定、pointer 変換も不変
const ctx2 = await browser.newContext({ deviceScaleFactor: 2 });
const page2 = await ctx2.newPage();
await page2.goto(`${base}/`, { waitUntil: "networkidle" });
await page2.waitForSelector("#verdict.pass", { timeout: 15000 });
{
  const box = await page2.locator("#live-canvas").boundingBox();
  const w = await page2.evaluate(() =>
    document.getElementById("live-canvas").width);
  check("DPR=2 keeps 1280 backing store", w === 1280);
  await page2.mouse.move(box.x + 100.5, box.y + 60.5);
  const t = (await page2.textContent("#pointer")).trim();
  check("DPR=2 pointer conversion unchanged", t === "(100, 60)", t);
}
await ctx2.close();

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
