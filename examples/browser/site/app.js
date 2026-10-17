// raden Vector Playground — host 層。
// 描画計算は raden-browser.js (MoonBit) に委譲し、ここでは
// DOM 操作・canonical バイト比較・表示変換だけを行う。
// Canvas の path/gradient API へ描画を委譲しない (pixel 転送のみ)。

import * as raden from "./raden-browser.js";
import {
  inputHash, prgbToRgba, compareBytes,
  stateFromQuery, stateToQuery, clientToImagePx,
} from "./core.js";

// =============================================================================
// アプリ状態
// =============================================================================

const CUSTOM_PRESET = "custom";

const $ = (id) => document.getElementById(id);
const els = {
  preset: $("preset"), width: $("width"), height: $("height"),
  frame: $("frame"), fps: $("fps"),
  zoom: $("zoom"), zoomV: $("zoom-v"), checker: $("checker"),
  stepBack: $("step-back"), stepFwd: $("step-fwd"),
  redraw: $("redraw"), reset: $("reset"), download: $("download"),
  refCanvas: $("ref-canvas"), liveCanvas: $("live-canvas"),
  overlay: $("live-overlay"), customWrap: $("custom-controls"),
  verdict: $("verdict"), inputHashEl: $("input-hash"),
  refSha: $("ref-sha"), liveSha: $("live-sha"),
  diff: $("diff"), detail: $("detail"), info: $("candidate-info"),
  pointer: $("pointer"),
  c: {
    fillRule: $("c-fill-rule"),
    tx: $("c-tx"), ty: $("c-ty"), sx: $("c-sx"), sy: $("c-sy"), rotate: $("c-rotate"),
    clip: $("c-clip"), clipX: $("c-clip-x"), clipY: $("c-clip-y"),
    clipW: $("c-clip-w"), clipH: $("c-clip-h"),
    paintKind: $("c-paint-kind"), color: $("c-color"), alpha: $("c-alpha"),
    stop0: $("c-stop0"), stop1: $("c-stop1"),
    stroke: $("c-stroke"), strokeWidth: $("c-stroke-width"),
    cap: $("c-cap"), join: $("c-join"), dash: $("c-dash"),
    compOp: $("c-comp-op"), overlay: $("c-overlay"),
    resetPoints: $("c-reset-points"),
  },
};

let manifest = null;
// 現在のリクエスト識別子。古い結果の適用を防ぐため常に比較する。
let requestSeq = 0;
// 適用済みの最新リクエスト id。これより古い結果は破棄する。
let appliedSeq = 0;
// custom scene の 4 制御点 (画像ピクセル座標、512x512 既定)。
let customPoints = defaultPoints();
// ドラッグ中の制御点 index (-1 は非ドラッグ)。
let dragIndex = -1;

function defaultPoints() {
  // 自己交差する五芒星。NonZero は中心も塗り、EvenOdd は穴になる。
  return [256, 66, 368, 410, 75, 197, 437, 197, 144, 410];
}

function clampInt(v, lo, hi) {
  return Math.max(lo, Math.min(hi, parseInt(v, 10) || 0));
}

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function parseDash(text) {
  return text.split(/[,\s]+/).map((v) => Number(v))
    .filter((v) => Number.isFinite(v) && v >= 0);
}

function customSpec() {
  const w = parseInt(els.width.value, 10) || 512;
  const h = parseInt(els.height.value, 10) || 512;
  const solid = hexToRgb(els.c.color.value);
  const s0 = hexToRgb(els.c.stop0.value);
  const s1 = hexToRgb(els.c.stop1.value);
  const spec = {
    points: customPoints.slice(),
    fill_rule: els.c.fillRule.value,
    matrix: {
      tx: Number(els.c.tx.value) || 0,
      ty: Number(els.c.ty.value) || 0,
      sx: Number(els.c.sx.value) || 1,
      sy: Number(els.c.sy.value) || 1,
      rotate: Number(els.c.rotate.value) || 0,
    },
    clip: els.c.clip.checked ? {
      x: Number(els.c.clipX.value) || 0,
      y: Number(els.c.clipY.value) || 0,
      w: Number(els.c.clipW.value) || 1,
      h: Number(els.c.clipH.value) || 1,
    } : null,
    paint: els.c.paintKind.value === "linear" ? {
      kind: "linear", x0: 0, y0: 0, x1: w, y1: h,
      stops: [
        { offset: 0, ...s0, a: 255 },
        { offset: 1, ...s1, a: 255 },
      ],
    } : {
      kind: "solid", ...solid,
      a: clampInt(els.c.alpha.value, 0, 255),
    },
    stroke: els.c.stroke.checked ? {
      width: Number(els.c.strokeWidth.value) || 0,
      cap: els.c.cap.value,
      join: els.c.join.value,
      dash: parseDash(els.c.dash.value),
      dash_offset: 0,
    } : null,
    comp_op: els.c.compOp.value,
    overlay: els.c.overlay.value,
  };
  return spec;
}

function currentState() {
  const custom = els.preset.value === CUSTOM_PRESET ? JSON.stringify(customSpec()) : "";
  return {
    preset: els.preset.value,
    w: parseInt(els.width.value, 10) || 0,
    h: parseInt(els.height.value, 10) || 0,
    frame: parseInt(els.frame.value, 10) || 0,
    fps: parseInt(els.fps.value, 10) || 0,
    custom,
  };
}

function setVerdict(kind, text) {
  els.verdict.className = `v verdict ${kind}`;
  els.verdict.textContent = text;
}

function setDetail(msg) { els.detail.textContent = msg; }

function clearRef() {
  const c = els.refCanvas;
  c.width = 1;
  c.height = 1;
  c.getContext("2d").clearRect(0, 0, 1, 1);
}

function syncOverlay(w, h, zoom) {
  const o = els.overlay;
  o.width = w;
  o.height = h;
  o.style.width = `${Math.round(w * zoom)}px`;
  o.style.height = `${Math.round(h * zoom)}px`;
  drawHandles();
}

function drawHandles() {
  const o = els.overlay;
  const ctx = o.getContext("2d");
  ctx.clearRect(0, 0, o.width, o.height);
  if (els.preset.value !== CUSTOM_PRESET) return;
  if (els.c.clip.checked) {
    ctx.strokeStyle = "rgba(255, 200, 80, 0.9)";
    ctx.lineWidth = 1;
    ctx.strokeRect(
      Number(els.c.clipX.value) || 0, Number(els.c.clipY.value) || 0,
      Number(els.c.clipW.value) || 0, Number(els.c.clipH.value) || 0,
    );
  }
  const n = Math.floor(customPoints.length / 2);
  for (let i = 0; i < n; i++) {
    const x = customPoints[i * 2];
    const y = customPoints[i * 2 + 1];
    ctx.beginPath();
    ctx.arc(x, y, 7, 0, Math.PI * 2);
    ctx.fillStyle = i === dragIndex ? "#ffd24a" : "#ffffff";
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = "#101320";
    ctx.stroke();
    ctx.fillStyle = "#101320";
    ctx.font = "10px monospace";
    ctx.fillText(String(i + 1), x + 9, y - 9);
  }
}

// canonical RGBA8 を canvas に転送する (表示専用)。
function showOnCanvas(canvas, rgba8, w, h, zoom) {
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  const img = new ImageData(new Uint8ClampedArray(prgbToRgba(rgba8).buffer), w, h);
  ctx.putImageData(img, 0, 0);
  // CSS 表示サイズ = ピクセルサイズ × zoom。backing store は触らない。
  canvas.style.width = `${Math.round(w * zoom)}px`;
  canvas.style.height = `${Math.round(h * zoom)}px`;
  if (canvas === els.liveCanvas) syncOverlay(w, h, zoom);
}

async function loadReference(state) {
  if (state.preset === CUSTOM_PRESET) {
    return { kind: "no_reference", reason: "custom scene has no Rust reference" };
  }
  // 参照は preset + canonical サイズに対してのみ存在する。
  // 任意編集状態に対しては参照を捏造せず NO_REFERENCE を返す。
  const entry = manifest.examples[state.preset];
  if (!entry) return { kind: "no_reference", reason: "preset not in manifest" };
  // 参照は (scene, 寸法, frame) の組にのみ存在する。
  // 対応する参照がなければ「参照なし」を返し、元 preset の画像を流用しない。
  const refEntry = (entry.references || []).find((r) =>
    r.width === state.w && r.height === state.h && r.frame === state.frame
  );
  if (!refEntry) {
    return { kind: "no_reference", reason: `no reference for ${state.w}x${state.h} frame ${state.frame}` };
  }
  const resp = await fetch(`./reference/${refEntry.file}`);
  if (!resp.ok) {
    return { kind: "missing", reason: `reference fetch failed: ${resp.status}` };
  }
  const bytes = new Uint8Array(await resp.arrayBuffer());
  if (bytes.length !== state.w * state.h * 4) {
    return { kind: "missing", reason: `reference size mismatch: ${bytes.length}` };
  }
  // manifest に記録された sha と実体の sha を照合する。
  // 旧 manifest や差し替えられた参照を PASS と誤認しないための検査。
  const actual = raden.sha256_hex(bytes);
  if (actual !== refEntry.sha256) {
    return { kind: "stale", reason: `reference sha ${actual.slice(0, 12)}.. != manifest ${refEntry.sha256.slice(0, 12)}..` };
  }
  return { kind: "ok", bytes, sha: refEntry.sha256 };
}

async function renderAndCompare() {
  const state = currentState();
  const ihash = inputHash(state);
  const seq = ++requestSeq;
  els.inputHashEl.textContent = ihash;

  // 参照は非同期。MoonBit 描画は同期 (重い場合は将来 Worker 化)。
  // live 描画が失敗して early return しても reject が浮かないよう
  // ここで一度 handler を付けておく (await 側では引き続き reject を観測できる)。
  const refPromise = loadReference(state);
  refPromise.catch(() => {});
  const r = state.preset === CUSTOM_PRESET
    ? raden.render_custom_rgba8(JSON.stringify(customSpec()), state.w, state.h)
    : raden.render_scene_rgba8(
      state.preset, state.w, state.h, BigInt(state.frame), BigInt(state.fps),
    );
  if (!(r._0 instanceof Uint8Array)) {
    if (seq <= appliedSeq) return; // 古い結果は破棄
    appliedSeq = seq;
    setVerdict("err", "RENDER ERROR");
    els.liveSha.textContent = "-";
    setDetail(raden.error_message(r._0));
    return;
  }
  const liveBytes = r._0;
  const liveSha = raden.sha256_hex(liveBytes);
  showOnCanvas(els.liveCanvas, liveBytes, state.w, state.h, els.zoom.value / 100);
  els.liveSha.textContent = liveSha;
  // 入力状態を URL に反映して再読み込み・共有で復元可能にする。
  const qstate = { ...state, zoom: els.zoom.value };
  if (state.preset === CUSTOM_PRESET) qstate.points = customPoints;
  history.replaceState(null, "", stateToQuery(qstate));

  // fetch 自体の失敗 (abort/ネットワーク断) も missing として扱う。
  // ここで握りつぶさないと古い PASS 表示が残ってしまう。
  let ref;
  try {
    ref = await refPromise;
  } catch (e) {
    ref = { kind: "missing", reason: `reference fetch failed: ${e.message}` };
  }
  if (seq <= appliedSeq) return; // その間に新しい入力があった
  appliedSeq = seq;

  if (ref.kind === "ok") {
    els.refSha.textContent = ref.sha;
    showOnCanvas(els.refCanvas, ref.bytes, state.w, state.h, els.zoom.value / 100);
    const cmp = compareBytes(liveBytes, ref.bytes);
    if (cmp.equal) {
      setVerdict("pass", "PASS");
      els.diff.textContent = "0 bytes differ";
      setDetail(`live sha == reference sha (fixture: ${state.preset})`);
    } else {
      setVerdict("fail", "FAIL");
      els.diff.textContent =
        `${cmp.diffBytes} bytes differ (first at ${cmp.firstDiff})`;
      setDetail("canonical raw bytes mismatch");
    }
  } else {
    els.refSha.textContent = "-";
    clearRef();
    setVerdict(
      "noref",
      ref.kind === "missing" ? "REF MISSING"
        : ref.kind === "stale" ? "REF STALE"
        : "NO REFERENCE",
    );
    els.diff.textContent = "-";
    setDetail(ref.reason);
  }
}

function applyZoom() {
  const z = els.zoom.value;
  els.zoomV.textContent = `${z}%`;
  for (const c of [els.refCanvas, els.liveCanvas]) {
    c.style.width = `${Math.round(c.width * z / 100)}px`;
    c.style.height = `${Math.round(c.height * z / 100)}px`;
  }
  els.overlay.style.width = `${Math.round(els.overlay.width * z / 100)}px`;
  els.overlay.style.height = `${Math.round(els.overlay.height * z / 100)}px`;
}

function applyChecker() {
  for (const el of document.querySelectorAll(".canvas-wrap")) {
    el.classList.toggle("checker", els.checker.checked);
  }
}

function updateCustomVisibility() {
  els.customWrap.hidden = els.preset.value !== CUSTOM_PRESET;
  drawHandles();
}

function selectPreset(name) {
  if (name === CUSTOM_PRESET) {
    els.width.value = 512;
    els.height.value = 512;
    els.frame.value = 0;
    els.fps.value = 60;
    updateCustomVisibility();
    return;
  }
  const entry = manifest.examples[name];
  // canonical 寸法は先頭参照 (fixture 定義サイズ) から取る。
  const ref0 = (entry.references || [])[0];
  els.width.value = ref0 ? ref0.width : 1280;
  els.height.value = ref0 ? ref0.height : 720;
  els.frame.value = ref0 ? ref0.frame : 0;
  els.fps.value = 60;
  updateCustomVisibility();
}

function resetCustomPoints() {
  customPoints = defaultPoints();
  drawHandles();
  renderAndCompare();
}

function reset() {
  els.preset.value = "basic_drawing";
  selectPreset("basic_drawing");
  customPoints = defaultPoints();
  els.zoom.value = 100;
  els.checker.checked = true;
  applyZoom();
  applyChecker();
  setVerdict("uncompared", "UNCOMPARED");
  els.inputHashEl.textContent = "-";
  els.refSha.textContent = "-";
  els.liveSha.textContent = "-";
  els.diff.textContent = "-";
  setDetail("-");
  renderAndCompare();
}

function bindCustomControls() {
  const handler = () => {
    if (els.preset.value === CUSTOM_PRESET) {
      drawHandles();
      renderAndCompare();
    }
  };
  for (const el of Object.values(els.c)) {
    if (el === els.c.resetPoints) continue;
    el.addEventListener("input", handler);
    el.addEventListener("change", handler);
  }
  els.c.resetPoints.addEventListener("click", resetCustomPoints);
}

function bindPointerEditing() {
  els.liveCanvas.addEventListener("mousedown", (e) => {
    if (els.preset.value !== CUSTOM_PRESET) return;
    const p = clientToImagePx(els.liveCanvas, e.clientX, e.clientY);
    if (!p) return;
    let best = -1;
    let bestD = 20;
    const n = Math.floor(customPoints.length / 2);
    for (let i = 0; i < n; i++) {
      const dx = p.x - customPoints[i * 2];
      const dy = p.y - customPoints[i * 2 + 1];
      const d = Math.hypot(dx, dy);
      if (d < bestD) { bestD = d; best = i; }
    }
    if (best >= 0) {
      dragIndex = best;
      drawHandles();
      e.preventDefault();
    }
  });
  els.liveCanvas.addEventListener("mousemove", (e) => {
    const p = clientToImagePx(els.liveCanvas, e.clientX, e.clientY);
    els.pointer.textContent = p ? `(${p.x}, ${p.y})` : "-";
    if (dragIndex >= 0 && p && els.preset.value === CUSTOM_PRESET) {
      customPoints[dragIndex * 2] = p.x;
      customPoints[dragIndex * 2 + 1] = p.y;
      drawHandles();
      renderAndCompare();
    }
  });
  const endDrag = () => {
    if (dragIndex >= 0) {
      dragIndex = -1;
      drawHandles();
    }
  };
  els.liveCanvas.addEventListener("mouseup", endDrag);
  els.liveCanvas.addEventListener("mouseleave", () => {
    endDrag();
    els.pointer.textContent = "-";
  });
  els.overlay.addEventListener("mousemove", (e) => {
    // overlay は pointer-events none なのでここには来ない (将来の拡張用)。
    void e;
  });
}

async function boot() {
  const resp = await fetch("./manifest.json");
  manifest = await resp.json();
  for (const name of Object.keys(manifest.examples)) {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    els.preset.appendChild(opt);
  }
  const customOpt = document.createElement("option");
  customOpt.value = CUSTOM_PRESET;
  customOpt.textContent = "custom (no reference)";
  els.preset.appendChild(customOpt);
  els.info.textContent = `[${raden.candidate_info()}] manifest: ${manifest.generated_from}`;
  els.preset.addEventListener("change", () => { selectPreset(els.preset.value); renderAndCompare(); });
  for (const el of [els.width, els.height, els.frame, els.fps]) {
    el.addEventListener("change", renderAndCompare);
  }
  // ポインタ座標を画像ピクセル単位で表示 (zoom/scroll/DPR 非依存)。
  for (const c of [els.refCanvas, els.liveCanvas]) {
    c.addEventListener("mousemove", (e) => {
      const p = clientToImagePx(c, e.clientX, e.clientY);
      els.pointer.textContent = p ? `(${p.x}, ${p.y})` : "-";
    });
  }
  els.refCanvas.addEventListener("mouseleave", () => { els.pointer.textContent = "-"; });
  els.zoom.addEventListener("input", applyZoom);
  els.checker.addEventListener("change", applyChecker);
  els.redraw.addEventListener("click", renderAndCompare);
  // freeze/step: 決定的な時間刻み (frame_index 固定) での前後移動。
  const step = (d) => {
    const v = Math.max(0, (parseInt(els.frame.value, 10) || 0) + d);
    els.frame.value = v;
    renderAndCompare();
  };
  els.stepBack.addEventListener("click", () => step(-1));
  els.stepFwd.addEventListener("click", () => step(1));
  els.reset.addEventListener("click", reset);
  els.download.addEventListener("click", () => {
    const a = document.createElement("a");
    a.download = `${currentState().preset}.png`;
    a.href = els.liveCanvas.toDataURL("image/png");
    a.click();
  });
  bindCustomControls();
  bindPointerEditing();
  // URL query からの状態復元 (リロード・共有リンク対応)。
  const restored = stateFromQuery(location.search, {
    preset: "basic_drawing", w: 1280, h: 720, frame: 0, fps: 60, zoom: 100,
  });
  if (restored.points) customPoints = restored.points.slice();
  if (restored.preset === CUSTOM_PRESET) {
    els.preset.value = CUSTOM_PRESET;
    updateCustomVisibility();
    els.width.value = restored.w;
    els.height.value = restored.h;
    els.frame.value = restored.frame;
    els.fps.value = restored.fps;
    renderAndCompare();
  } else if (manifest.examples[restored.preset]) {
    els.preset.value = restored.preset;
    els.width.value = restored.w;
    els.height.value = restored.h;
    els.frame.value = restored.frame;
    els.fps.value = restored.fps;
    updateCustomVisibility();
    renderAndCompare();
  } else {
    reset();
  }
  if (restored.zoom >= 10 && restored.zoom <= 400) {
    els.zoom.value = restored.zoom;
    els.zoomV.textContent = `${restored.zoom}%`;
    applyZoom();
  }
  applyChecker();
  // E2E / デバッグ用: 現在の custom spec を読み出せるようにする。
  window.__radenCustom = {
    points: () => customPoints.slice(),
    spec: () => customSpec(),
    setPoints: (pts) => { customPoints = pts.slice(); drawHandles(); renderAndCompare(); },
  };
}

boot();
