// Vector Playground の純粋ロジック (DOM・canvas 非依存)。
// node から直接検証できるよう app.js とは別モジュールに分離する。

// 入力状態のハッシュ。参照画像・判定結果の対応付けに使う。
// fnv-1a 32bit。同じ入力なら同じハッシュになる。
export function inputHash(state) {
  const extra = state.custom || (state.points ? state.points.join(",") : "");
  const s = `${state.preset}|${state.w}x${state.h}|f${state.frame}|fps${state.fps}|${extra}`;
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0");
}

// canonical premultiplied RGBA8 → canvas 表示用 straight RGBA8。
// 描画コアではなく表示変換。alpha 0 はそのまま、255 も恒等。
export function prgbToRgba(src) {
  const out = new Uint8Array(src.length);
  for (let i = 0; i < src.length; i += 4) {
    const a = src[i + 3];
    if (a === 0 || a === 255) {
      out[i] = src[i]; out[i + 1] = src[i + 1];
      out[i + 2] = src[i + 2]; out[i + 3] = a;
      continue;
    }
    // c_premult = c * a / 255 の逆変換 (四捨五入)。
    out[i] = Math.min(255, Math.round((src[i] * 255) / a));
    out[i + 1] = Math.min(255, Math.round((src[i + 1] * 255) / a));
    out[i + 2] = Math.min(255, Math.round((src[i + 2] * 255) / a));
    out[i + 3] = a;
  }
  return out;
}

// canonical バイト列同士の比較。canvas 読み出しではなく raw bytes で行う。
export function compareBytes(a, b) {
  if (a.length !== b.length) {
    return { equal: false, diffBytes: -1, firstDiff: -1, reason: "length" };
  }
  let diff = 0;
  let first = -1;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      diff++;
      if (first < 0) first = i;
    }
  }
  return { equal: diff === 0, diffBytes: diff, firstDiff: first };
}

// URL query → 入力状態の部分復元。未知キー・不正値は無視する。
export function stateFromQuery(search, defaults) {
  const q = new URLSearchParams(search);
  const s = { ...defaults };
  if (q.has("preset")) s.preset = q.get("preset");
  for (const k of ["w", "h", "frame", "fps", "zoom"]) {
    if (q.has(k)) {
      const v = parseInt(q.get(k), 10);
      if (Number.isFinite(v)) s[k] = v;
    }
  }
  if (q.has("p")) {
    const pts = q.get("p").split(",").map((v) => Number(v));
    if (pts.length >= 6 && pts.length % 2 === 0 && pts.every((v) => Number.isFinite(v))) s.points = pts;
  }
  return s;
}

// 入力状態 → URL query 文字列 (? 付き、履歴復元用)。
export function stateToQuery(s) {
  const q = new URLSearchParams();
  q.set("preset", s.preset);
  q.set("w", String(s.w));
  q.set("h", String(s.h));
  q.set("frame", String(s.frame));
  q.set("fps", String(s.fps));
  if (s.zoom !== undefined) q.set("zoom", String(s.zoom));
  if (s.points !== undefined) q.set("p", s.points.join(","));
  return `?${q.toString()}`;
}

// client 座標 (pointer event) → 画像ピクセル座標。
// CSS 表示サイズ・スクロール・DPR を canvas.getBoundingClientRect() が
// 全て吸収するので、実ピクセル / CSS ピクセルの比だけを掛ける。
// canvas 外の座標は null を返す (編集点ドラッグ等に誤適用しないため)。
export function clientToImagePx(canvas, clientX, clientY) {
  const r = canvas.getBoundingClientRect();
  if (r.width === 0 || r.height === 0) return null;
  const x = Math.floor(((clientX - r.left) / r.width) * canvas.width);
  const y = Math.floor(((clientY - r.top) / r.height) * canvas.height);
  if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height) return null;
  return { x, y };
}
