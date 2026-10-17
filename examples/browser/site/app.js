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

const $ = (id) => document.getElementById(id);
const els = {
  preset: $("preset"), width: $("width"), height: $("height"),
  frame: $("frame"), fps: $("fps"),
  zoom: $("zoom"), zoomV: $("zoom-v"), checker: $("checker"),
  stepBack: $("step-back"), stepFwd: $("step-fwd"),
  redraw: $("redraw"), reset: $("reset"), download: $("download"),
  refCanvas: $("ref-canvas"), liveCanvas: $("live-canvas"),
  verdict: $("verdict"), inputHashEl: $("input-hash"),
  refSha: $("ref-sha"), liveSha: $("live-sha"),
  diff: $("diff"), detail: $("detail"), info: $("candidate-info"),
  pointer: $("pointer"),
};

let manifest = null;
// 現在のリクエスト識別子。古い結果の適用を防ぐため常に比較する。
let requestSeq = 0;
// 適用済みの最新リクエスト id。これより古い結果は破棄する。
let appliedSeq = 0;

function currentState() {
  return {
    preset: els.preset.value,
    w: parseInt(els.width.value, 10) || 0,
    h: parseInt(els.height.value, 10) || 0,
    frame: parseInt(els.frame.value, 10) || 0,
    fps: parseInt(els.fps.value, 10) || 0,
  };
}

function setVerdict(kind, text) {
  els.verdict.className = `v verdict ${kind}`;
  els.verdict.textContent = text;
}

function setDetail(msg) { els.detail.textContent = msg; }

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
}

async function loadReference(state) {
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
  const r = raden.render_scene_rgba8(
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
  history.replaceState(null, "", stateToQuery({ ...state, zoom: els.zoom.value }));

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
}

function applyChecker() {
  for (const el of document.querySelectorAll(".canvas-wrap")) {
    el.classList.toggle("checker", els.checker.checked);
  }
}

function selectPreset(name) {
  const entry = manifest.examples[name];
  // canonical 寸法は先頭参照 (fixture 定義サイズ) から取る。
  const ref0 = (entry.references || [])[0];
  els.width.value = ref0 ? ref0.width : 1280;
  els.height.value = ref0 ? ref0.height : 720;
  els.frame.value = ref0 ? ref0.frame : 0;
  els.fps.value = 60;
}

function reset() {
  els.preset.value = "basic_drawing";
  selectPreset("basic_drawing");
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

async function boot() {
  const resp = await fetch("./manifest.json");
  manifest = await resp.json();
  for (const name of Object.keys(manifest.examples)) {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    els.preset.appendChild(opt);
  }
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
    c.addEventListener("mouseleave", () => { els.pointer.textContent = "-"; });
  }
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
  // URL query からの状態復元 (リロード・共有リンク対応)。
  const restored = stateFromQuery(location.search, {
    preset: "basic_drawing", w: 1280, h: 720, frame: 0, fps: 60, zoom: 100,
  });
  if (manifest.examples[restored.preset]) {
    els.preset.value = restored.preset;
    els.width.value = restored.w;
    els.height.value = restored.h;
    els.frame.value = restored.frame;
    els.fps.value = restored.fps;
  }
  if (restored.zoom >= 10 && restored.zoom <= 400) {
    els.zoom.value = restored.zoom;
    els.zoomV.textContent = `${restored.zoom}%`;
  }
  applyChecker();
  if (manifest.examples[restored.preset]) {
    renderAndCompare();
  } else {
    reset();
  }
}

boot();
