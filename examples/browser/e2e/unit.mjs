// core.js の純粋ロジック検証 (DOM 不要、node で直接実行)。
// canonical premultiplied → straight alpha 変換は alpha 0/1/128/255 の
// 端点を必ず押さえる (issue の受け入れ条件)。
import { inputHash, prgbToRgba, compareBytes, stateFromQuery, stateToQuery }
  from "../site/core.js";

const results = [];
const check = (name, ok, detail = "") => {
  results.push(ok);
  console.log(`${ok ? "ok" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

// --- prgbToRgba: alpha 端点 ---
// alpha=0: premultiplied では RGB も 0。straight でも恒等 (0 割り回避)。
{
  const out = prgbToRgba(new Uint8Array([0, 0, 0, 0]));
  check("alpha=0 passthrough", out[0] === 0 && out[3] === 0);
}
// alpha=1: 最小非ゼロ。RGB 各 channel は premult 値 1 → round(1*255/1)=255 上限。
{
  const out = prgbToRgba(new Uint8Array([1, 0, 0, 1]));
  check("alpha=1 un-premultiply", out[0] === 255 && out[3] === 1,
    `r=${out[0]}`);
}
// alpha=128: 半分。premult 64 → round(64*255/128)=128、
// premult 96 → round(96*255/128)=round(191.25)=191。
{
  const out = prgbToRgba(new Uint8Array([64, 32, 96, 128]));
  check("alpha=128 restores", out[0] === 128 && out[1] === 64 && out[2] === 191,
    `${[...out]}`);
}
// alpha=255: 恒等変換。
{
  const src = new Uint8Array([10, 20, 30, 255]);
  const out = prgbToRgba(src);
  check("alpha=255 identity",
    out[0] === 10 && out[1] === 20 && out[2] === 30 && out[3] === 255);
}
// premult RGB > alpha はあり得ないが、変換結果は 255 クランプ。
{
  const out = prgbToRgba(new Uint8Array([200, 200, 200, 100]));
  check("clamps to 255", out[0] === 255 && out[3] === 100);
}

// --- compareBytes ---
{
  const a = new Uint8Array([1, 2, 3, 4]);
  check("identical bytes equal", compareBytes(a, a).equal === true);
  const b = new Uint8Array([1, 9, 3, 4]);
  const r = compareBytes(a, b);
  check("diff detected", !r.equal && r.firstDiff === 1 && r.diffBytes === 1);
  const r2 = compareBytes(a, new Uint8Array([1, 2]));
  check("length mismatch -> not equal", !r2.equal && r2.reason === "length");
}

// --- inputHash ---
{
  const s = { preset: "basic_drawing", w: 1280, h: 720, frame: 0, fps: 60 };
  check("hash stable", inputHash(s) === inputHash({ ...s }));
  check("hash 8-hex", /^[0-9a-f]{8}$/.test(inputHash(s)));
  check("diff state -> diff hash",
    inputHash(s) !== inputHash({ ...s, frame: 1 }));
  check("diff size -> diff hash",
    inputHash(s) !== inputHash({ ...s, w: 640 }));
}

// --- stateFromQuery / stateToQuery 往復 ---
{
  const d = { preset: "x", w: 1, h: 1, frame: 0, fps: 60, zoom: 100 };
  const s = { preset: "stroke_drawing", w: 640, h: 360, frame: 30, fps: 24, zoom: 150 };
  const back = stateFromQuery(stateToQuery(s), d);
  check("query roundtrip",
    back.preset === "stroke_drawing" && back.w === 640 && back.h === 360 &&
    back.frame === 30 && back.fps === 24 && back.zoom === 150,
    JSON.stringify(back));
  // 空 query はデフォルトを返す
  const e = stateFromQuery("", d);
  check("empty query -> defaults", e.preset === "x" && e.zoom === 100);
  // 不正値は無視してデフォルト
  const bad = stateFromQuery("?w=abc&frame=-3x", d);
  check("invalid values ignored", bad.w === 1 && bad.frame === -3 || bad.frame === 0);
}

const failed = results.filter((r) => !r).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
