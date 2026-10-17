import { ActuatorView } from "./actuator3d.js";
import { Encoding, VQC, MLP, ModelFF, PDOnly } from "./policy.js";
import { Run, sampleRandomPlant } from "./sim.js";
import { StripChart, ProbBars, buildCircuit } from "./viz.js";

const $ = (id) => document.getElementById(id);
const DEG = 180 / Math.PI;

const [POL, RES, REF, HW] = await Promise.all(["data/policies.json", "data/results.json", "data/reference.json", "data/hw_openloop.json"]
  .map((u) => fetch(u).then((r) => r.json())));
const P = POL.plant;
const enc = new Encoding(POL.encoding);
const makePolicy = (name) => ({
  vqc: () => new VQC(POL.vqc, enc), mlp: () => new MLP(POL.mlp, enc),
  model_ff: () => new ModelFF(P, enc.tauMax), pd: () => new PDOnly(),
}[name]());
const COLORS = { pd: "#9aa0a6", model_ff: "#4c78a8", vqc: "#e45756", mlp: "#f58518", mlp_l: "#54a24b" };
const NAMES = { pd: "PD only", model_ff: "PD + model FF", vqc: "PD + VQC (72)", mlp: "PD + MLP (65)" };

// ------------------------------------------------------------------ 3D views
const views = [];
function addView(id, opts) {
  const v = new ActuatorView($(id), opts);
  v.visible = true;
  new IntersectionObserver(([e]) => { v.visible = e.isIntersecting; }, { rootMargin: "100px" }).observe($(id));
  views.push(v);
  return v;
}
const hero = addView("hero3d", { autoRotate: true, labels: false, dial: false, cameraPos: [300, 150, 330] });
hero.controls.target.set(45, 0, -15);
if (window.innerWidth < 1100) { hero.camera.position.multiplyScalar(1.35); hero.controls.target.set(35, 10, -15); }
const act = addView("act3d", { labels: true, dial: false, ghost: false, cameraPos: [330, 150, 40] });
act.controls.target.set(0, 0, -15);
const simView = addView("sim3d", { labels: false, cameraPos: [40, 60, 560] });
simView.controls.target.set(40, 0, 0);

// ------------------------------------------------------------------ hero: background VQC run
let heroRun = new Run(P, makePolicy("vqc"), { traj: "sine", amp: 0.3, freq: 0.5 });

// ------------------------------------------------------------------ actuator section
let actAnimate = true, actT = 0;
$("explode").addEventListener("input", (e) => { act.explodeTarget = +e.target.value; });
$("cutaway").addEventListener("change", (e) => act.setCutaway(e.target.checked));
$("spin").addEventListener("change", (e) => { actAnimate = e.target.checked; });
$("manualQ").addEventListener("input", (e) => { $("spin").checked = false; actAnimate = false; act.setState(+e.target.value, +e.target.value); });

// ------------------------------------------------------------------ simulator
const ui = {
  policy: $("policy"), traj: $("traj"), amp: $("amp"), freq: $("freq"), J: $("J"), tau_c: $("tau_c"), delay: $("delay"), speed: $("speed"),
};
function setPlantUI(p) {
  ui.J.value = p.J; ui.tau_c.value = p.tau_c; ui.delay.value = p.delay;
  plantExtra = { b: p.b, eta: p.eta };
  refreshLabels();
}
let plantExtra = { b: P.nominal.b, eta: P.nominal.eta };
function refreshLabels() {
  $("ampV").textContent = `${(+ui.amp.value).toFixed(2)} rad`;
  $("freqV").textContent = `${(+ui.freq.value).toFixed(2)} Hz`;
  $("JV").textContent = `${(+ui.J.value).toFixed(4)} kg·m²`;
  $("tcV").textContent = `${(+ui.tau_c.value).toFixed(2)} N·m`;
  $("dlV").textContent = `${ui.delay.value} ms`;
}
function currentPlant() {
  return { J: +ui.J.value, tau_c: +ui.tau_c.value, delay: +ui.delay.value, b: plantExtra.b, eta: plantExtra.eta };
}
function simOpts() { return { traj: ui.traj.value, amp: +ui.amp.value, freq: +ui.freq.value, plant: currentPlant() }; }

const charts = {
  pos: new StripChart($("cPos"), { yLabel: "deg", series: [{ color: "#9be7a0", scale: DEG, width: 3.5 }, { color: "#5aa9ff", scale: DEG, width: 1.6 }] }),
  err: new StripChart($("cErr"), { yLabel: "mrad", series: [{ color: "#f2b84b", scale: 1e3 }] }),
  tau: new StripChart($("cTau"), { yLabel: "N·m", series: [{ color: "#e45756" }, { color: "#c7c7c7", width: 1 }] }),
};
let run, vizVQC = new VQC(POL.vqc, enc), paused = false;
function restart() {
  run = new Run(P, makePolicy(ui.policy.value), simOpts());
  Object.values(charts).forEach((c) => c.clear());
  $("mParams").textContent = run.policy.nParams || "0";
}
setPlantUI({ ...P.nominal });
restart();
for (const k of ["policy", "traj", "amp", "freq", "J", "tau_c", "delay"]) ui[k].addEventListener("input", () => { refreshLabels(); restart(); });
$("restart").addEventListener("click", restart);
$("pause").addEventListener("click", (e) => { paused = !paused; e.target.textContent = paused ? "Resume" : "Pause"; });
$("randPlant").addEventListener("click", () => { setPlantUI(sampleRandomPlant(P)); restart(); });
$("nomPlant").addEventListener("click", () => { setPlantUI({ ...P.nominal }); restart(); });

// ------------------------------------------------------------------ VQC panel
const circuit = buildCircuit($("circuit"), ["integrated error", "ref. velocity", "ref. acceleration", "joint velocity", "ref. position", "tracking error e"]);
const probBars = new ProbBars($("cProb"));
function updateVQCPanel(obs) {
  const tau = vizVQC.act(obs);
  circuit.update(vizVQC.x);
  probBars.draw(vizVQC.prob, vizVQC.z);
  const z = vizVQC.z;
  const zb = $("zBar"), tb = $("tBar");
  zb.style.left = `${50 + Math.min(0, z) * 50}%`; zb.style.width = `${Math.abs(z) * 50}%`;
  tb.style.left = `${50 + Math.min(0, tau / enc.tauMax) * 50}%`; tb.style.width = `${Math.abs(tau / enc.tauMax) * 50}%`;
  $("zVal").textContent = z.toFixed(3);
  $("tVal").textContent = `${tau.toFixed(3)} N·m`;
}

// ------------------------------------------------------------------ head-to-head comparison
function mulberry32(a) { return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
let compareChart = null;
async function runComparison(nPlants = 24, seconds = 4) {
  const btn = $("compareBtn"); btn.disabled = true;
  const rnd = mulberry32(7), plants = Array.from({ length: nPlants }, () => sampleRandomPlant(P, rnd));
  const order = ["pd", "model_ff", "vqc", "mlp"], out = {};
  for (const name of order) {
    out[name] = [];
    for (let i = 0; i < plants.length; i++) {
      btn.textContent = `Running ${NAMES[name]} · plant ${i + 1}/${nPlants}`;
      const r = new Run(P, makePolicy(name), { traj: ui.traj.value, amp: +ui.amp.value, freq: +ui.freq.value, plant: plants[i] });
      for (let k = 0; k < seconds * 1000; k++) r.tick();
      out[name].push(r.rmsMrad);
      if (i % 4 === 3) await new Promise((res) => setTimeout(res, 0));
    }
  }
  const mean = (a) => a.reduce((s, v) => s + v, 0) / a.length;
  const data = order.map((n) => mean(out[n]));
  if (compareChart) compareChart.destroy();
  compareChart = new Chart($("cCompare"), {
    type: "bar",
    data: { labels: order.map((n) => NAMES[n]), datasets: [
      { label: "mean RMS error [mrad]", data, backgroundColor: order.map((n) => COLORS[n]) },
      { type: "scatter", label: "individual plants", data: order.flatMap((n, i) => out[n].map((v) => ({ x: NAMES[n], y: v }))), backgroundColor: "rgba(255,255,255,.55)", pointRadius: 2.5 },
    ] },
    options: chartOpts({ y: "RMS tracking error [mrad] (t ≥ 1 s)", logY: true, valueLabels: true }),
  });
  btn.disabled = false; btn.textContent = "Run again";
  window.__compare = { order, out, data };
  return window.__compare;
}
$("compareBtn").addEventListener("click", () => runComparison());

// ------------------------------------------------------------------ static result charts
Chart.defaults.color = "#93a1bd";
Chart.defaults.borderColor = "#24314f";
Chart.defaults.font.family = "Inter, Segoe UI, system-ui, sans-serif";
const valueLabelPlugin = {
  id: "valueLabels",
  afterDatasetsDraw(chart, _, opts) {
    if (!opts || !opts.enabled) return;
    const { ctx } = chart;
    chart.data.datasets.forEach((ds, di) => {
      if (ds.type === "scatter" || ds.type === "line") return;
      chart.getDatasetMeta(di).data.forEach((bar, i) => {
        const v = ds.data[i]; if (v == null) return;
        ctx.save(); ctx.fillStyle = "#e7ecf6"; ctx.font = "600 11px Inter, system-ui"; ctx.textAlign = "center";
        const horiz = chart.options.indexAxis === "y";
        const txt = (opts.fmt || ((x) => (x >= 100 ? x.toFixed(0) : x.toFixed(2))))(v);
        if (horiz) { ctx.textAlign = "left"; ctx.fillText(txt, bar.x + 6, bar.y + 4); } else ctx.fillText(txt, bar.x, bar.y - 6);
        ctx.restore();
      });
    });
  },
};
Chart.register(valueLabelPlugin);
function chartOpts({ y = "", x = "", logY = false, horizontal = false, valueLabels = false, fmt, max } = {}) {
  return {
    responsive: true, maintainAspectRatio: false, animation: false, indexAxis: horizontal ? "y" : "x",
    plugins: { legend: { display: false }, valueLabels: { enabled: valueLabels, fmt } },
    scales: {
      x: horizontal ? { type: "linear", min: 0, max, title: { display: !!x, text: x } }
        : { type: "category", title: { display: !!x, text: x }, grid: { display: false } },
      y: horizontal ? { type: "category", grid: { display: false } }
        : { type: logY ? "logarithmic" : "linear", title: { display: !!y, text: y }, beginAtZero: !logY },
    },
    layout: { padding: { top: 18, right: horizontal ? 40 : 6 } },
  };
}
function staticCharts() {
  const pc = RES.policy_comparison;
  const EN = { pd: "PD only", model_ff: "PD + model FF", vqc: "PD + VQC (72)", mlp_s: "PD + MLP 6-8-1 (65)", mlp_l: "PD + MLP 6-64-64-1 (4,673)" };
  const col = { pd: COLORS.pd, model_ff: COLORS.model_ff, vqc: COLORS.vqc, mlp_s: COLORS.mlp, mlp_l: COLORS.mlp_l };
  new Chart($("cPolicy"), {
    type: "bar",
    data: { labels: pc.map((r) => EN[r.color]), datasets: [{ data: pc.map((r) => r.rms_mean), backgroundColor: pc.map((r) => col[r.color]) }] },
    options: chartOpts({ y: "RMS tracking error [mrad]", valueLabels: true }),
  });
  const vqc = pc.find((r) => r.color === "vqc"), mlp = pc.find((r) => r.color === "mlp_s");
  $("gapTxt").textContent = `${Math.round((100 * (vqc.rms_mean - mlp.rms_mean)) / vqc.rms_mean)} %`;
  const it = RES.hls_iterations;
  new Chart($("cHls"), {
    type: "bar",
    data: { labels: ["v1 baseline", "v2 partition+unroll", "v3 no flatten", "v4 ping-pong", "v5 final"], datasets: [{ data: it.map((i) => i.latency_us), backgroundColor: it.map((i) => (i.timing_met ? "#54a24b" : "#e45756")) }] },
    options: chartOpts({ y: "µs", valueLabels: true, fmt: (v) => v.toFixed(1) }),
  });
  const t = RES.timing_us;
  new Chart($("cLat"), {
    type: "bar",
    data: { labels: ["PL path (C)", "PS kernel (C)", "PL via Python", "PS via Python"],
      datasets: [{ data: [t.pl_path_c, t.kernel_ps_c, t.policy_pl_python_p50, t.policy_ps_python_p50], backgroundColor: ["#b279a2", "#4c78a8", "#d7a8cb", "#8fb0d6"] }] },
    options: chartOpts({ y: "p50 latency [µs]", valueLabels: true, fmt: (v) => v.toFixed(1) }),
  });
  const b = RES.bitstream_vqc_can0;
  new Chart($("cRes"), {
    type: "bar",
    data: { labels: ["LUT", "FF", "DSP", "BRAM"], datasets: [{ data: [b.lut_pct, b.ff_pct, b.dsp_pct, b.bram_pct], backgroundColor: ["#5aa9ff", "#5aa9ff", "#e45756", "#5aa9ff"] }] },
    options: chartOpts({ x: "% of XC7Z020", horizontal: true, valueLabels: true, max: 100, fmt: (v) => `${v.toFixed(1)} %` }),
  });
}
staticCharts();

// ------------------------------------------------------------------ real-hardware run (2026-10-13, open loop)
function hwCharts() {
  const line = (label, data, color, width = 1.6, dash) => ({ label, data, borderColor: color, backgroundColor: color,
    borderWidth: width, borderDash: dash, pointRadius: 0, tension: 0 });
  const xy = (ys) => HW.t.map((t, i) => ({ x: t, y: ys[i] }));
  const timeOpts = (y) => ({
    responsive: true, maintainAspectRatio: false, animation: false, parsing: false,
    plugins: { legend: { display: true, labels: { boxWidth: 12 } } },
    scales: { x: { type: "linear", min: 0, max: 20, title: { display: true, text: "time [s]" } },
      y: { type: "linear", title: { display: true, text: y } } },
  });
  new Chart($("cHwAngle"), {
    type: "line",
    data: { datasets: [{ ...line("commanded", xy(HW.q_cmd), "#9be7a0", 4), order: 2 }, { ...line("applied by firmware (reply)", xy(HW.q_applied), "#1f6fd1", 1.6, [5, 3]), order: 1 }] },
    options: timeOpts("output angle [rad] (command, not measured)"),
  });
  new Chart($("cHwCur"), {
    type: "line",
    data: { datasets: [line("|i_phase| [A]", xy(HW.i_phase), "#f2b84b", 1.2), line("drive amplitude [V]", xy(HW.voltage), "#c7c7c7", 1.2, [4, 3])] },
    options: timeOpts("A / V"),
  });
  const h = RES.hw_openloop_2026_10_13, t = RES.timing_us;
  new Chart($("cHwRtt"), {
    type: "bar",
    data: {
      labels: ["PS CAN0 loopback\n(on-chip, emulated ESC)", "CANable USB\nmotor power off", "CANable USB\nmotor running"],
      datasets: [
        { label: "p50", data: [t.can_pingpong_p50, h.rtt_us_no_motor_power.p50, h.rtt_us.p50], backgroundColor: "#5aa9ff" },
        { label: "p99", data: [t.can_pingpong_p99, h.rtt_us_no_motor_power.p99, h.rtt_us.p99], backgroundColor: "#e45756" },
        { type: "line", label: "1 ms control period", data: [1000, 1000, 1000], borderColor: "#f2b84b", borderDash: [6, 4], pointRadius: 0, borderWidth: 2 },
      ],
    },
    options: { ...chartOpts({ y: "round-trip time [µs]", valueLabels: true, fmt: (v) => v.toFixed(0) }),
      plugins: { legend: { display: true, labels: { boxWidth: 12 } }, valueLabels: { enabled: true, fmt: (v) => v.toFixed(0) } } },
  });
  $("hwFrames").textContent = `${h.frames.toLocaleString("en-US")} / ${h.missed}`;
  $("hwRtt").textContent = `${h.rtt_us.p50} / ${h.rtt_us.p99} / ${h.rtt_us.max} µs`;
  const im = HW.i_phase.reduce((a, b) => a + b, 0) / HW.i_phase.length;
  $("hwImean").textContent = h.phase_current_a.mean.toFixed(2);
  $("hwImax").textContent = h.phase_current_a.max.toFixed(2);
  window.__hw = { points: HW.t.length, imeanDecimated: im };
}
hwCharts();

// ------------------------------------------------------------------ main loop
let last = performance.now(), frame = 0;
function loop(now) {
  const dtReal = Math.min(0.05, (now - last) / 1000); last = now; frame++;
  // hero
  for (let k = 0; k < Math.round(dtReal * 1000); k++) heroRun.tick();
  if (heroRun.k > 40000) heroRun = new Run(P, makePolicy("vqc"), { traj: "sine", amp: 0.3, freq: 0.5 });
  hero.setState(heroRun.q, heroRun.last.qRef);
  // actuator section
  if (actAnimate) { actT += dtReal; const q = 0.9 * Math.sin(actT * 0.6); act.setState(q, q); $("manualQ").value = q.toFixed(2); }
  const qa = act.q;
  $("kinReadout").textContent = `motor ${(-15 * qa * DEG).toFixed(0)}° · disc spin ${(qa * DEG).toFixed(1)}° · output ${(qa * DEG).toFixed(1)}°`;
  // simulator
  if (!paused) {
    const n = Math.min(400, Math.round(dtReal * 1000 * +ui.speed.value));
    let s;
    for (let k = 0; k < n; k++) {
      s = run.tick();
      if (k % 5 === 0) { charts.pos.push(s.t, [s.qRef, s.q]); charts.err.push(s.t, [s.err]); charts.tau.push(s.t, [s.tau, s.tauMeas]); }
    }
    if (s) {
      simView.setState(s.q, s.qRef);
      $("mRms").textContent = run.n ? `${run.rmsMrad.toFixed(2)} mrad` : "warming up";
      $("mMax").textContent = run.n ? `${run.maxMrad.toFixed(2)} mrad` : "–";
      $("mTau").textContent = `${s.tau.toFixed(3)} N·m`;
      if (frame % 2 === 0) updateVQCPanel(s.obs);
    }
  }
  Object.values(charts).forEach((c) => c.draw());
  for (const v of views) if (v.visible && v.ready) v.render();
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);

// ------------------------------------------------------------------ self-test hooks (used by tools/verify_site.py)
window.VQCLab = {
  ready: () => views.every((v) => v.ready),
  policyCheck() {
    const v = new VQC(POL.vqc, enc), m = new MLP(POL.mlp, enc), f = new ModelFF(P, enc.tauMax);
    let ev = 0, em = 0, ef = 0;
    REF.obs.forEach((o, i) => {
      ev = Math.max(ev, Math.abs(v.act(o) - REF.vqc_tau[i]));
      em = Math.max(em, Math.abs(m.act(o) - REF.mlp_tau[i]));
      ef = Math.max(ef, Math.abs(f.act(o) - REF.model_ff[i]));
    });
    return { vqc: ev, mlp: em, model_ff: ef };
  },
  loopCheck() {
    const out = {};
    for (const name of ["pd", "model_ff", "vqc", "mlp"]) {
      const r = new Run(P, makePolicy(name), { traj: "sine", amp: 0.3, freq: 0.5 });
      for (let k = 0; k < 4000; k++) r.tick();
      out[name] = { js: r.rmsMrad, py: REF.loops[name].rms_mrad };
    }
    return out;
  },
  runComparison,
  advance(seconds) {            // deterministic fast-forward of the simulator (used for screenshots)
    let s;
    for (let k = 0; k < seconds * 1000; k++) {
      s = run.tick();
      if (k % 5 === 0) { charts.pos.push(s.t, [s.qRef, s.q]); charts.err.push(s.t, [s.err]); charts.tau.push(s.t, [s.tau, s.tauMeas]); }
    }
    simView.setState(s.q, s.qRef); updateVQCPanel(s.obs);
    return { t: s.t, rms: run.rmsMrad };
  },
  pause(on) { paused = on; },
  setup(o) {
    for (const k in o) if (ui[k]) ui[k].value = o[k];
    refreshLabels(); restart();
  },
  views: { hero, act, simView },
};
document.body.dataset.ready = "1";
