"""Generate the measured-result figures for docs/ (v2.0).

    python docs/tools/make_figures.py

Inputs:  docs/results/results.json, docs/results/logs/*.csv
Outputs: docs/figures/png/*.png (overwrites the v1.0 figures that showed assumed data,
         adds new ones). Conceptual figures (circuit, gearbox, bit-vs-qubit ...) are kept.
"""
import csv
import json
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import FancyBboxPatch  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
OUT = os.path.join(DOCS, "figures", "png")
RES = json.load(open(os.path.join(DOCS, "results", "results.json"), encoding="utf-8"))
plt.rcParams.update({"font.family": ["Segoe UI", "DejaVu Sans"], "axes.unicode_minus": False, "font.size": 10,
                     "axes.spines.top": False, "axes.spines.right": False})
C = {"pd": "#9aa0a6", "model_ff": "#4c78a8", "vqc": "#e45756", "mlp_s": "#f58518", "mlp_l": "#54a24b",
     "pl": "#b279a2", "ps": "#4c78a8", "can": "#72b7b2", "ink": "#222222"}


def save(fig, name):
    fig.savefig(os.path.join(OUT, name), dpi=150, bbox_inches="tight", facecolor="white")
    fig.savefig(os.path.join(os.path.dirname(OUT), "svg", name.replace(".png", ".svg")), bbox_inches="tight",
                facecolor="white")
    plt.close(fig)
    print("wrote", name)


def box(ax, x, y, w, h, text, fc, fs=9, weight="normal"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.006,rounding_size=0.015",
                                fc=fc, ec="#555555", lw=1))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs, weight=weight, wrap=True)


def arrow(ax, x0, y0, x1, y1, text="", fs=8):
    ax.annotate("", xy=(x1, y1), xytext=(x0, y0), arrowprops=dict(arrowstyle="->", lw=1.3, color="#333"))
    if text:
        ax.text((x0 + x1) / 2, (y0 + y1) / 2 + 0.015, text, ha="center", va="bottom", fontsize=fs)


def fig1_architecture():
    fig, ax = plt.subplots(figsize=(11, 6.2))
    ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.axis("off")
    ax.add_patch(FancyBboxPatch((0.01, 0.30), 0.56, 0.60, boxstyle="round,pad=0.005", fc="#f4f6fb", ec="#888"))
    ax.text(0.29, 0.875, "PYNQ-Z2 (XC7Z020)", ha="center", weight="bold")
    box(ax, 0.025, 0.60, 0.245, 0.24, "PS: Cortex-A9 Linux\nrun_controller.py\n1 kHz, SCHED_FIFO\ntrajectory · obs · safety",
        "#dde7f7")
    box(ax, 0.31, 0.60, 0.245, 0.24, "PL: vqc_top (HLS)\n6 qubits · 4 layers · 72 params\ncore 22.5 µs @100 MHz\npath 29 µs (PS C 65 µs)",
        "#f6dfe6")
    arrow(ax, 0.275, 0.72, 0.305, 0.72)
    box(ax, 0.025, 0.33, 0.245, 0.2, "PS CAN0 (xilinx_can)\n1 Mbps, SP 0.8\nref clk 100 MHz", "#e3f1ef")
    box(ax, 0.31, 0.33, 0.245, 0.2, "EMIO → Pmod JA\nJA1=TX (Y18)\nJA2=RX (Y19)", "#e3f1ef")
    arrow(ax, 0.15, 0.595, 0.15, 0.535)
    arrow(ax, 0.275, 0.43, 0.305, 0.43)
    box(ax, 0.62, 0.35, 0.16, 0.16, "SN65HVD230 (PS CAN)\nnot working\nused: CANable USB", "#fff4d6")
    arrow(ax, 0.56, 0.43, 0.615, 0.43)
    box(ax, 0.62, 0.62, 0.36, 0.26, "B-G431B-ESC1 (Recoil, new board 10-13)\nMODE_POSITION, 2 kHz (needs encoder):\nτ = kp·(q_ref - q) - kd·dq + τ_ff\n"
        "EMA α=0.27 → FOC 10 kHz", "#e8e8e8")
    arrow(ax, 0.70, 0.515, 0.70, 0.615)
    ax.text(0.715, 0.565, "RPDO3 [q_ref, τ_ff]\nTPDO3 [q, τ]", ha="left", va="center", fontsize=8)
    box(ax, 0.62, 0.06, 0.36, 0.2, "MAD 5010 110KV + 15:1 cycloidal\nopen-loop drive only (no encoder, 10-13)", "#eeeeee")
    arrow(ax, 0.90, 0.615, 0.90, 0.265)
    box(ax, 0.025, 0.06, 0.53, 0.18, "Substitute verification paths (measurement basis of this edition)\n• --sim: in-process firmware emulator + joint model\n"
        "• CAN loopback + virtual_recoil.py: via the real Zynq CAN controller", "#fafafa", fs=8.5)
    ax.set_title("Figure 1. System architecture (v2.4, residual structure) — gray boxes: real hardware driven open-loop only", weight="bold", fontsize=11)
    save(fig, "fig1-system-architecture.png")


def fig3_policy_comparison():
    rows = RES["policy_comparison"]
    names = [r["label"] for r in rows]
    vals = [r["rms_mean"] for r in rows]
    errs = [r.get("rms_std", 0) for r in rows]
    cols = [C[r["color"]] for r in rows]
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4.2), gridspec_kw={"width_ratios": [1.4, 1]})
    b = a1.bar(range(len(rows)), vals, yerr=errs, color=cols, capsize=4)
    a1.set_xticks(range(len(rows)), names, fontsize=8.5)
    a1.set_ylabel("RMS tracking error [mrad]")
    a1.set_title("Simulated tracking error (domain randomization, 256 episodes × 3 s)")
    for rect, v in zip(b, vals):
        a1.text(rect.get_x() + rect.get_width() / 2, v + max(vals) * 0.02, f"{v:.2f}", ha="center", fontsize=8.5)
    learned = [r for r in rows if r.get("params")]
    a2.scatter([r["params"] for r in learned], [r["rms_mean"] for r in learned],
               c=[C[r["color"]] for r in learned], s=70, zorder=3)
    for r in learned:
        a2.annotate(f'{r["label"].split(chr(10))[0]}\n{r["params"]} params', (r["params"], r["rms_mean"]),
                    textcoords="offset points", xytext=(6, 4), fontsize=8)
    a2.set_xscale("log"); a2.set_xlabel("Trainable parameters (log)"); a2.set_ylabel("RMS error [mrad]")
    a2.set_title("Performance vs. parameter count")
    a2.grid(alpha=0.3); a2.margins(x=0.15, y=0.18)
    fig.suptitle("Figure 3. VQC vs. MLP vs. classical baselines (measured in simulation)", weight="bold")
    fig.tight_layout()
    save(fig, "fig3-vqc-vs-mlp.png")


def fig5_timing_budget():
    t = RES["timing_us"]
    items = [("PS policy compute\n(ctypes C kernel)", t["policy_ps_python_p50"], C["ps"]),
             ("PL policy compute\n(incl. MMIO)", t.get("policy_pl_python_p50"), C["pl"]),
             ("CAN round trip\n(loopback ping-pong p50)", t["can_pingpong_p50"], C["can"]),
             ("CAN round trip, est.\n(real ESC, 350–420)", t["can_rtt_expected"], "#c7e9e5")]
    items = [i for i in items if i[1] is not None]
    fig, ax = plt.subplots(figsize=(9, 3.6))
    ax.barh(range(len(items)), [i[1] for i in items], color=[i[2] for i in items])
    ax.set_yticks(range(len(items)), [i[0] for i in items])
    ax.axvline(1000, color="k", ls="--", lw=1); ax.text(1000, len(items) - 0.4, " 1 ms period", va="bottom")
    for k, i in enumerate(items):
        ax.text(i[1] + 10, k, f"{i[1]:.0f} µs", va="center", fontsize=9)
    ax.set_xlabel("µs"); ax.invert_yaxis(); ax.set_xlim(0, 1150)
    ax.set_title("Figure 5. Time used within the 1 kHz period (measured, PYNQ-Z2)", weight="bold")
    save(fig, "fig5-timing-budget.png")


def fig_hls_progress():
    it = RES["hls_iterations"]
    fig, ax = plt.subplots(figsize=(9, 3.8))
    x = range(len(it))
    ax.bar(x, [i["latency_us"] for i in it], color=[("#54a24b" if i["timing_met"] else "#e45756") for i in it])
    ax.set_xticks(list(x), [i["label"] for i in it], fontsize=8.5)
    for k, i in enumerate(it):
        ax.text(k, i["latency_us"] + 4, f'{i["latency_us"]:.1f} µs\n{i["clock_ns"]:.1f} ns, LUT {i["lut_pct"]}%',
                ha="center", fontsize=8)
    ax.axhline(RES["timing_us"]["kernel_ps_c"], color=C["ps"], ls="--", lw=1)
    ax.text(len(it) - 0.5, RES["timing_us"]["kernel_ps_c"] + 3, "PS C kernel", color=C["ps"], ha="right", fontsize=8.5)
    ax.set_ylabel("Inference latency [µs] (HLS estimate)"); ax.set_ylim(0, max(i["latency_us"] for i in it) * 1.25)
    ax.set_title("Figure 14. VQC core latency per HLS optimization step (green = 100 MHz timing met)", weight="bold")
    save(fig, "fig14-hls-optimization.png")


def load_csv(name):
    with open(os.path.join(DOCS, "results", "logs", name)) as f:
        rows = list(csv.DictReader(f))
    return {k: [float(r[k]) for r in rows] for k in rows[0]}


def fig_tracking():
    fig, ax = plt.subplots(2, 1, figsize=(10, 5.6), sharex=True)
    for name, lab, col in (("sim_pd.csv", "PD only", C["pd"]), ("sim_model_ff.csv", "PD+model FF", C["model_ff"]),
                           ("sim_vqc.csv", "PD+VQC", C["vqc"])):
        d = load_csv(name)
        n = min(len(d["t"]), 4000)
        ax[0].plot(d["t"][:n], [1e3 * (r - q) for r, q in zip(d["q_ref"][:n], d["q"][:n])], color=col, lw=1, label=lab)
        ax[1].plot(d["t"][:n], d["tau_ff"][:n], color=col, lw=1, label=lab)
    ax[0].set_ylabel("Tracking error [mrad]"); ax[0].legend(fontsize=8, ncol=3); ax[0].grid(alpha=0.3)
    ax[1].set_ylabel("τ_ff [N·m]"); ax[1].set_xlabel("t [s]"); ax[1].grid(alpha=0.3)
    fig.suptitle("Figure 15. 1 kHz control run on the PYNQ-Z2 (0.3 rad, 0.5 Hz sine, 1 s initial ramp)", weight="bold")
    fig.tight_layout()
    save(fig, "fig15-tracking-pynq.png")


def fig7_timeline():
    rows = [("09-20", "P1 Firmware bring-up", "ok"), ("10-03", "P2 ESC SWD unresponsive → cause: soldering overheat (confirmed 10-07)", "fail"),
            ("10-04", "P3 PYNQ SD image", "ok"), ("10-05", "P4 PYNQ bring-up · PS CAN0", "ok"),
            ("10-05", "P5 Host SW · emulator", "ok"), ("10-05~06", "P6 VQC training (residual structure)", "ok"),
            ("10-06", "P7 Vivado 2024.1 · HLS · bitstream", "ok"), ("10-06", "P8 MLP comparison · PL measurement", "ok"),
            ("10-13", "P9 New ESC · open-loop drive PYNQ→CANable→ESC (no encoder)", "ok"),
            ("TBD", "Closed-loop test (needs AS5600 encoder, 1 kHz CAN path)", "todo")]
    col = {"ok": "#54a24b", "fail": "#e45756", "todo": "#bbbbbb"}
    fig, ax = plt.subplots(figsize=(10, 4.6))
    for k, (d, t, st_) in enumerate(rows):
        y = len(rows) - k
        ax.scatter([0], [y], s=180, color=col[st_], zorder=3)
        ax.text(0.15, y, d, va="center", fontsize=9.5, color="#555")
        ax.text(1.2, y, t, va="center", fontsize=10)
    ax.plot([0, 0], [0.6, len(rows) + 0.4], color="#ccc", zorder=1)
    ax.set_xlim(-0.3, 6); ax.set_ylim(0.4, len(rows) + 0.6); ax.axis("off")
    ax.set_title("Figure 7. Actual development timeline (2026; green done · red failed/unresolved · gray not done)", weight="bold")
    save(fig, "fig7-timeline.png")


if __name__ == "__main__":
    fig7_timeline()
    os.makedirs(OUT, exist_ok=True)
    fig1_architecture()
    fig_hls_progress()
    fig_tracking()
    if "policy_comparison" in RES:
        fig3_policy_comparison()
    fig5_timing_budget()
