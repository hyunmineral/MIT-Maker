// Lightweight canvas/SVG visualisations: live strip charts, the VQC circuit and
// the 64-amplitude probability bars.

const css = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

export class StripChart {
  // series: [{key, label, color, scale}] ; window in seconds
  constructor(canvas, { series, window = 4, yLabel = "", range = null, symmetric = true }) {
    this.c = canvas; this.ctx = canvas.getContext("2d");
    this.series = series; this.window = window; this.yLabel = yLabel;
    this.range = range; this.symmetric = symmetric;
    this.t = []; this.data = series.map(() => []);
  }
  push(t, values) {
    this.t.push(t);
    values.forEach((v, i) => this.data[i].push(v));
    const t0 = t - this.window;
    let cut = 0;
    while (cut < this.t.length && this.t[cut] < t0) cut++;
    if (cut > 0) { this.t.splice(0, cut); this.data.forEach((d) => d.splice(0, cut)); }
  }
  clear() { this.t = []; this.data = this.series.map(() => []); }
  draw() {
    const c = this.c, ctx = this.ctx, dpr = window.devicePixelRatio || 1;
    const W = c.clientWidth, H = c.clientHeight;
    if (c.width !== W * dpr || c.height !== H * dpr) { c.width = W * dpr; c.height = H * dpr; }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const L = 58, R = 8, T = 8, B = 20, pw = W - L - R, ph = H - T - B;
    let lo = Infinity, hi = -Infinity;
    if (this.range) [lo, hi] = this.range;
    else {
      this.data.forEach((d, i) => d.forEach((v) => { const s = v * (this.series[i].scale || 1); lo = Math.min(lo, s); hi = Math.max(hi, s); }));
      if (!isFinite(lo)) { lo = -1; hi = 1; }
      if (this.symmetric) { const m = Math.max(Math.abs(lo), Math.abs(hi), 1e-6) * 1.15; lo = -m; hi = m; }
      else { const pad = (hi - lo) * 0.1 || 1; lo -= pad; hi += pad; }
    }
    const grid = css("--grid"), muted = css("--muted");
    ctx.strokeStyle = grid; ctx.lineWidth = 1; ctx.fillStyle = muted; ctx.font = "11px Inter, system-ui, sans-serif";
    for (let k = 0; k <= 4; k++) {
      const y = T + (ph * k) / 4, v = hi - ((hi - lo) * k) / 4;
      ctx.beginPath(); ctx.moveTo(L, y); ctx.lineTo(L + pw, y); ctx.stroke();
      ctx.textAlign = "right"; ctx.fillText(Math.abs(v) >= 100 ? v.toFixed(0) : v.toFixed(Math.abs(v) >= 10 ? 1 : 2), L - 6, y + 4); ctx.textAlign = "left";
    }
    ctx.save(); ctx.translate(11, T + ph / 2); ctx.rotate(-Math.PI / 2); ctx.textAlign = "center"; ctx.fillText(this.yLabel, 0, 0); ctx.restore();
    if (this.t.length < 2) return;
    const t1 = this.t[this.t.length - 1], t0 = t1 - this.window;
    const X = (t) => L + ((t - t0) / this.window) * pw, Y = (v) => T + ((hi - v) / (hi - lo)) * ph;
    this.series.forEach((s, i) => {
      ctx.strokeStyle = s.color; ctx.lineWidth = s.width || 1.6; ctx.setLineDash(s.dash || []);
      ctx.beginPath();
      this.data[i].forEach((v, j) => { const x = X(this.t[j]), y = Y(v * (s.scale || 1)); j ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
      ctx.stroke();
    });
    ctx.setLineDash([]);
    ctx.fillStyle = muted; ctx.fillText(`t = ${t1.toFixed(1)} s`, L + pw - 64, H - 5);
  }
}

export class ProbBars {
  constructor(canvas) { this.c = canvas; this.ctx = canvas.getContext("2d"); }
  draw(prob, z) {
    const c = this.c, ctx = this.ctx, dpr = window.devicePixelRatio || 1;
    const W = c.clientWidth, H = c.clientHeight;
    if (c.width !== W * dpr || c.height !== H * dpr) { c.width = W * dpr; c.height = H * dpr; }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const n = prob.length, bw = (W - 20) / n, base = H - 22, top = 10;
    let pmax = 0; for (const p of prob) pmax = Math.max(pmax, p);
    pmax = Math.max(pmax, 0.05);
    for (let i = 0; i < n; i++) {
      const h = (prob[i] / pmax) * (base - top);
      ctx.fillStyle = i < n / 2 ? css("--c-plus") : css("--c-minus");
      ctx.fillRect(10 + i * bw + 0.5, base - h, Math.max(1, bw - 1.5), h);
    }
    ctx.fillStyle = css("--muted"); ctx.font = "11px Inter, system-ui, sans-serif";
    ctx.fillText("|000000⟩", 10, H - 6);
    ctx.textAlign = "center"; ctx.fillText("qubit 0 = |0⟩   │   qubit 0 = |1⟩", W / 2, H - 6);
    ctx.textAlign = "right"; ctx.fillText("|111111⟩", W - 10, H - 6); ctx.textAlign = "left";
    ctx.strokeStyle = css("--grid"); ctx.beginPath(); ctx.moveTo(W / 2, top); ctx.lineTo(W / 2, base); ctx.stroke();
  }
}

// Static SVG of one data-reuploading layer (×4) with live encoding angles.
export function buildCircuit(svg, featureNames) {
  const NS = "http://www.w3.org/2000/svg";
  const el = (tag, attrs, text) => { const e = document.createElementNS(NS, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); if (text !== undefined) e.textContent = text; svg.appendChild(e); return e; };
  const W = 760, rowH = 40, top = 30, H = top + rowH * 6 + 20;
  svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
  const xs = { lbl: 8, ry: 175, rx: 265, ry2: 335, rz: 405, cn: 480, meas: 690 };
  const live = [];
  for (let q = 0; q < 6; q++) {
    const y = top + q * rowH + rowH / 2;
    el("line", { x1: 150, y1: y, x2: 715, y2: y, class: "wire" });
    el("text", { x: xs.lbl, y: y - 3, class: "c-feat" }, featureNames[q]);
    const v = el("text", { x: xs.lbl, y: y + 12, class: "c-val" }, "x = 0.00");
    el("text", { x: 135, y: y + 4, class: "c-ket", "text-anchor": "end" }, "|0⟩");
    const b = el("rect", { x: xs.ry - 30, y: y - 13, width: 60, height: 26, rx: 5, class: "g-enc" });
    el("text", { x: xs.ry, y: y + 4, class: "g-txt", "text-anchor": "middle" }, "RY(x" + q + ")");
    for (const [x, t] of [[xs.rx, "RX"], [xs.ry2, "RY"], [xs.rz, "RZ"]]) {
      el("rect", { x: x - 24, y: y - 13, width: 48, height: 26, rx: 5, class: "g-var" });
      el("text", { x, y: y + 4, class: "g-txt", "text-anchor": "middle" }, t + "(θ)");
    }
    live.push({ v, b });
  }
  // CNOT ring 0->1 ... 5->0
  for (let q = 0; q < 6; q++) {
    const x = xs.cn + q * 30, yc = top + q * rowH + rowH / 2, t = (q + 1) % 6, yt = top + t * rowH + rowH / 2;
    el("line", { x1: x, y1: yc, x2: x, y2: yt, class: "cnot" });
    el("circle", { cx: x, cy: yc, r: 4.5, class: "ctrl" });
    el("circle", { cx: x, cy: yt, r: 9, class: "targ" });
    el("line", { x1: x - 9, y1: yt, x2: x + 9, y2: yt, class: "cnot" });
    el("line", { x1: x, y1: yt - 9, x2: x, y2: yt + 9, class: "cnot" });
  }
  el("rect", { x: 150, y: 8, width: 520, height: H - 16, rx: 10, class: "layer-box" });
  el("text", { x: 660, y: 24, class: "c-feat", "text-anchor": "end" }, "× 4 layers (data re-uploading)");
  const y0 = top + rowH / 2;
  el("rect", { x: xs.meas - 18, y: y0 - 13, width: 40, height: 26, rx: 5, class: "g-meas" });
  el("text", { x: xs.meas + 2, y: y0 + 5, class: "g-txt", "text-anchor": "middle" }, "⟨Z⟩");
  return {
    update(x) {
      live.forEach((l, q) => {
        l.v.textContent = `x = ${x[q].toFixed(2)} rad`;
        const a = Math.min(1, Math.abs(x[q]) / Math.PI);
        l.b.style.fillOpacity = 0.25 + 0.75 * a;
      });
    },
  };
}
