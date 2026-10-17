// Vector Playground M2/M3 custom scene E2E (chromium headless)。
// custom preset の fill rule / matrix / clip / stroke / comp op / overlay と
// 制御点 drag、URL query 復元を DOM イベント経由で検証する。
//
// 使い方: node custom.mjs [base-url]

import { chromium } from "playwright";

const base = process.argv[2] || "http://localhost:8931";
const browser = await chromium.launch();
const page = await browser.newPage();
const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "ok" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

const sha = async () => (await page.textContent("#live-sha")).trim();
const verdict = async () => (await page.textContent("#verdict")).trim();
const points = async () => page.evaluate(() => window.__radenCustom.points());

async function waitReady() {
  await page.waitForFunction(() => {
    const v = document.getElementById("verdict").textContent.trim();
    return v !== "UNCOMPARED" && document.getElementById("live-sha").textContent.trim() !== "-";
  }, { timeout: 15000 });
}

async function waitShaChanged(prev) {
  await page.waitForFunction((p) => {
    const s = document.getElementById("live-sha").textContent.trim();
    return s !== "-" && s !== p;
  }, prev, { timeout: 15000 });
  return sha();
}

await page.goto(`${base}/`, { waitUntil: "networkidle" });
await waitReady();

// custom preset へ切替
await page.selectOption("#preset", "custom");
await page.waitForFunction(
  () => document.getElementById("verdict").textContent.trim() === "NO REFERENCE",
  { timeout: 15000 });
await waitReady();
check("custom preset -> NO REFERENCE", (await verdict()) === "NO REFERENCE");
check("custom controls visible", await page.isVisible("#custom-controls"));

const size = await page.evaluate(() => {
  const c = document.getElementById("live-canvas");
  const o = document.getElementById("live-overlay");
  return [c.width, c.height, o.width, o.height];
});
check("custom canvas and overlay are 512x512",
  size[0] === 512 && size[1] === 512 && size[2] === 512 && size[3] === 512,
  JSON.stringify(size));

let prev = await sha();

// fill rule
await page.selectOption("#c-fill-rule", "evenodd");
prev = await waitShaChanged(prev);
check("fill rule changes output", true);

// clip
await page.check("#c-clip");
prev = await waitShaChanged(prev);
check("clip changes output", true);

// matrix
await page.fill("#c-tx", "20");
await page.dispatchEvent("#c-tx", "input");
prev = await waitShaChanged(prev);
check("matrix translate changes output", true);

// stroke
await page.check("#c-stroke");
prev = await waitShaChanged(prev);
check("stroke changes output", true);
await page.selectOption("#c-cap", "round");
prev = await waitShaChanged(prev);
check("stroke cap changes output", true);
await page.fill("#c-dash", "16,6");
await page.dispatchEvent("#c-dash", "input");
prev = await waitShaChanged(prev);
check("dash changes output", true);

// comp op
await page.selectOption("#c-comp-op", "Multiply");
prev = await waitShaChanged(prev);
check("comp op changes output", true);

// overlay
await page.selectOption("#c-overlay", "edges");
prev = await waitShaChanged(prev);
check("edge overlay changes output", true);

// paint kind (linear gradient)
await page.selectOption("#c-paint-kind", "linear");
prev = await waitShaChanged(prev);
check("linear paint changes output", true);

// control point drag
const before = await points();
const rect = await page.evaluate(() => {
  const c = document.getElementById("live-canvas");
  const r = c.getBoundingClientRect();
  return { x: r.x, y: r.y, w: r.width, h: r.height };
});
const px = rect.x + (before[0] / 512) * rect.w;
const py = rect.y + (before[1] / 512) * rect.h;
await page.mouse.move(px, py);
await page.mouse.down();
await page.mouse.move(px + 40, py + 24, { steps: 5 });
await page.mouse.up();
const after = await points();
check("dragging a control point updates coordinates",
  after[0] !== before[0] || after[1] !== before[1],
  `${before.slice(0, 2)} -> ${after.slice(0, 2)}`);
prev = await waitShaChanged(prev);
check("dragging a control point re-renders", true);

// reset points
await page.click("#c-reset-points");
await page.waitForFunction((b) => {
  const p = window.__radenCustom.points();
  return p[0] === b[0] && p[1] === b[1];
}, before, { timeout: 15000 });
check("reset points restores defaults", true);

// URL query 復元 (custom preset + p=...)
await page.waitForFunction(() => location.search.includes("preset=custom") &&
  location.search.includes("p="), { timeout: 15000 });
const url = page.url();
await page.reload({ waitUntil: "networkidle" });
await waitReady();
check("custom preset restored from query",
  (await verdict()) === "NO REFERENCE" && (await points()).length >= 6,
  `${url} -> ${(await points()).length} points`);

// 不正な custom spec は RENDER ERROR ではなく UI 側で防ぐが、
// 最低 1 点を canvas 外へ出しても描画が継続することを確認する。
await page.evaluate(() => window.__radenCustom.setPoints([-50, -50, 500, 500, 100, 400, 400, 100]));
await waitReady();
check("out-of-bounds control point still renders", true);

// 結果集計
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
await browser.close();
if (failed.length) {
  for (const f of failed) console.error(`FAIL: ${f.name} — ${f.detail}`);
  process.exit(1);
}
