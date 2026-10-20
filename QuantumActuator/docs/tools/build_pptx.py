"""Build the v2.0 slide decks from the measured results.

    python docs/tools/build_pptx.py     -> actuator-vqc-control-report.pptx, guide-for-beginners.pptx
"""
import json
import os

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Emu, Pt

from QuantumActuator.docs.tools.office_clean import clean_theme_fonts

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
FIG = os.path.join(DOCS, "figures", "png")
R = json.load(open(os.path.join(DOCS, "results", "results.json"), encoding="utf-8"))
FONT = "Calibri"
NAVY, RED, GREY, LIGHT = RGBColor(0x1A, 0x1A, 0x2E), RGBColor(0xC0, 0x39, 0x2B), RGBColor(0x55, 0x55, 0x55), RGBColor(0xF2, 0xF4, 0xF8)
W, H = Emu(12192000), Emu(6858000)


def pc(name):
    for r in R["policy_comparison"]:
        if r["color"] == name:
            return r
    raise KeyError(name)


VQC = pc("vqc")
MLP_S = pc("mlp_s")
MLP_L = pc("mlp_l")
VQC_TXT = f"{VQC['rms_mean']:.2f} ± {VQC['rms_std']:.2f}"
GAP = round(100 * (VQC["rms_mean"] - MLP_S["rms_mean"]) / VQC["rms_mean"])


class Deck:
    def __init__(self):
        self.p = Presentation()
        self.p.slide_width, self.p.slide_height = W, H
        self.blank = self.p.slide_layouts[6]

    def _text(self, slide, x, y, w, h, lines, size=18, color=NAVY, bold=False, align=PP_ALIGN.LEFT):
        tb = slide.shapes.add_textbox(Emu(x), Emu(y), Emu(w), Emu(h))
        tf = tb.text_frame
        tf.word_wrap = True
        for i, line in enumerate(lines if isinstance(lines, list) else [lines]):
            par = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            par.alignment = align
            lvl = 0
            if isinstance(line, tuple):
                lvl, line = line
            bullet = line.startswith("• ")
            run = par.add_run()
            run.text = ("    " * lvl) + line
            run.font.name = FONT
            run.font.size = Pt(size - 2 * lvl)
            run.font.bold = bold or (line.startswith("**") and line.endswith("**"))
            if run.font.bold and line.startswith("**"):
                run.text = ("    " * lvl) + line.strip("*")
            run.font.color.rgb = color
            par.space_after = Pt(6 if bullet else 4)
        return tb

    def header(self, slide, title, sub=None):
        bar = slide.shapes.add_shape(1, 0, 0, W, Emu(900000))
        bar.fill.solid(); bar.fill.fore_color.rgb = NAVY; bar.line.fill.background()
        self._text(slide, 400000, 150000, 11400000, 600000, title, size=26, color=RGBColor(255, 255, 255), bold=True)
        if sub:
            self._text(slide, 400000, 960000, 11400000, 400000, sub, size=13, color=GREY)

    def title(self, title, subtitle, foot):
        s = self.p.slides.add_slide(self.blank)
        bg = s.shapes.add_shape(1, 0, 0, W, H)
        bg.fill.solid(); bg.fill.fore_color.rgb = NAVY; bg.line.fill.background()
        self._text(s, 700000, 2000000, 10800000, 1400000, title, size=34, color=RGBColor(255, 255, 255), bold=True)
        self._text(s, 700000, 3500000, 10800000, 900000, subtitle, size=18, color=RGBColor(0xDD, 0xE6, 0xF2))
        self._text(s, 700000, 5600000, 10800000, 600000, foot, size=13, color=RGBColor(0xAA, 0xB4, 0xC8))

    def bullets(self, title, lines, sub=None, size=18):
        s = self.p.slides.add_slide(self.blank)
        self.header(s, title, sub)
        self._text(s, 600000, 1450000, 11000000, 5100000, lines, size=size)
        return s

    def image(self, title, img, lines=None, sub=None, img_w=7200000, size=15):
        s = self.p.slides.add_slide(self.blank)
        self.header(s, title, sub)
        path = os.path.join(FIG, img)
        top = 1450000
        if lines:
            pic = s.shapes.add_picture(path, Emu(350000), Emu(top), width=Emu(img_w))
            if pic.height > Emu(5200000):
                ratio = 5200000 / pic.height
                pic.height, pic.width = Emu(5200000), Emu(int(pic.width * ratio))
            x = 350000 + pic.width + 250000
            self._text(s, x, top, W - x - 300000, 5100000, lines, size=size)
        else:
            pic = s.shapes.add_picture(path, 0, Emu(top), height=Emu(5200000))
            if pic.width > Emu(11400000):
                ratio = 11400000 / pic.width
                pic.width, pic.height = Emu(11400000), Emu(int(pic.height * ratio))
            pic.left = Emu(int((W - pic.width) / 2))
        return s

    def table(self, title, rows, sub=None, col_w=None, size=14, note=None):
        s = self.p.slides.add_slide(self.blank)
        self.header(s, title, sub)
        nr, nc = len(rows), len(rows[0])
        h = min(5000000, 420000 * nr)
        t = s.shapes.add_table(nr, nc, Emu(500000), Emu(1500000), Emu(11200000), Emu(h)).table
        for j in range(nc):
            if col_w:
                t.columns[j].width = Emu(int(11200000 * col_w[j]))
        for i, row in enumerate(rows):
            for j, val in enumerate(row):
                cell = t.cell(i, j)
                cell.text = str(val)
                for par in cell.text_frame.paragraphs:
                    for run in par.runs:
                        run.font.name = FONT
                        run.font.size = Pt(size)
                        run.font.bold = i == 0
                        run.font.color.rgb = RGBColor(255, 255, 255) if i == 0 else NAVY
                cell.fill.solid()
                cell.fill.fore_color.rgb = NAVY if i == 0 else (LIGHT if i % 2 else RGBColor(255, 255, 255))
        if note:
            self._text(s, 500000, 1500000 + h + 200000, 11200000, 900000, note, size=13, color=GREY)
        return s

    def image2(self, title, left, right, caps=("", ""), sub=None):
        s = self.p.slides.add_slide(self.blank)
        self.header(s, title, sub)
        for k, img in enumerate((left, right)):
            x = 350000 + k * 5800000
            pic = s.shapes.add_picture(os.path.join(FIG, img), Emu(x), Emu(1500000), width=Emu(5500000))
            if pic.height > Emu(4500000):
                r = 4500000 / pic.height
                pic.height, pic.width = Emu(4500000), Emu(int(pic.width * r))
            if caps[k]:
                self._text(s, x, 1500000 + pic.height + 80000, 5500000, 500000, caps[k], size=12, color=GREY)
        return s

    def save(self, name):
        out = os.path.join(DOCS, name)
        self.p.save(out)
        clean_theme_fonts(out)
        print("wrote", name, len(self.p.slides), "slides")


t = R["timing_us"]
bit = R["bitstream_vqc_can0"]


def report_deck():
    d = Deck()
    d.title("Robot Actuator Control with a Quantum-Circuit Policy\nDevelopment Report v2.0",
            "PYNQ-Z2 (Zynq-7020) · Recoil B-G431B-ESC1 · MAD 5010 + 15:1 cycloidal",
            "2026-10-06 · replaces v1.0 (assumed scenario) with measured results")
    d.bullets("Before reading this report", [
        "• v1.0 was a scenario that assumed the goals were met; v2.0 contains only actual implementation and measurement results.",
        "• On 2026-10-13 the real actuator moved for the first time with the new ESC (PYNQ → CANable → ESC, open loop). There is no encoder, so closed-loop and VQC hardware comparisons are not done yet.",
        "• What was measured",
        (1, "Real hardware: FPGA bitstream, PS CAN pin path, PL inference core, 1 kHz control loop"),
        (1, "ESC substitute: firmware emulator (in-process or over CAN loopback)"),
        (1, "Joint dynamics: simulation, joint values randomized over the estimated range"),
        "• \"Quantum\" means a parameterized quantum circuit (VQC) computed on a classical chip.",
    ])
    d.table("Key results", [
        ["Item", "Result"],
        ["Control structure", "Residual: firmware PD (2 kHz) + VQC feed-forward (1 kHz)"],
        ["VQC policy (72 parameters)", f"RMS {VQC_TXT} mrad — about 6x better than PD only (8.79)"],
        ["VQC vs MLP", f"MLP 6-8-1 (65 params) {MLP_S['rms_mean']:.2f} mrad → {GAP}% more accurate than VQC → hypothesis rejected"],
        ["PL core", f"{t['hls_core_cycles']:,} cycles = {t['hls_core_us']} µs @100 MHz, WNS +{bit['wns_ns']} ns"],
        ["PL inference path (C)", f"{t['pl_path_c']} µs (PS C {t['kernel_ps_c']} µs) · 2.2x · matches PS within ≤4e-7"],
        ["1 kHz loop jitter", "--sim + VQC-PL: p50 1.2 / p99 4.1 / max 4.7 µs"],
        ["Real motor drive", "Open loop only: 4,000 commands, 0 missed, RTT p50 1.81 ms (no encoder)"],
    ], col_w=[0.3, 0.7], size=15)
    d.table("Development goals and status", [
        ["#", "Goal", "Criterion", "Result"],
        ["G1", "Single-axis FOC control", "Mode switching, tracking", "⚠️ CAN mode switching and open-loop drive only (no encoder)"],
        ["G2", "PYNQ real-time host", "1 kHz, jitter < 20 µs", "⚠️ p99 4.1 µs with --sim+PL. Real bus not measured"],
        ["G3", "VQC on PL", "Inference < 10 µs", "⚠️ Core 22.5 µs, path 29 µs, matches PS within ≤4e-7"],
        ["G4", "vs MLP", "Error gap < 25 %, 50x fewer params", f"❌ Same-size MLP is {GAP}% more accurate"],
        ["G5", "Sim-to-real", "Runs on hardware without retraining", "⏳ Not tested on hardware"],
    ], col_w=[0.06, 0.22, 0.27, 0.45], size=14)
    d.image("System architecture (v2.0)", "fig1-system-architecture.png")
    d.bullets("Why we switched to a residual structure", [
        "• **v1.0: the VQC decided the entire torque**",
        (1, "PID imitation learning explained only about 74 % of label variance (MSE 0.014 / variance 0.053)"),
        (1, "The high-gain region near 0 is hard to reproduce with a smooth circuit function"),
        "• **v2.0: firmware PD stabilizes, the VQC adds only the feed-forward τ_ff**",
        (1, "Maps directly onto Recoil RPDO3 [q_ref, τ_ff]"),
        (1, "A wrong policy output only increases tracking error instead of destabilizing the joint → safer on hardware"),
        "• **τ_prev removed from the inputs**: output-feedback chatter dtau_rms 0.029 → 0.0026",
    ])
    d.image("VQC policy circuit", "fig2-vqc-circuit.png", [
        "• 6 qubits · 4 layers · 72 parameters",
        "• Layer: RY(x) → RX·RY·RZ(θ) → CNOT ring",
        "• 6 inputs: ∫e, q̇_ref, q̈_ref, q̇, q_ref, e",
        "• Output: τ_ff = 0.8·tanh(2⟨Z₀⟩)",
        "• The PS pre-combines RZ·RY·RX into 24 2×2 matrices and loads them into the PL",
    ], img_w=7000000)
    d.image("Actual development timeline", "fig7-timeline.png")
    d.image("Result ① Policy comparison — VQC vs MLP", "fig3-vqc-vs-mlp.png", None,
            sub=f"VQC {VQC_TXT} · MLP-65 {MLP_S['rms_mean']:.2f} ± {MLP_S['rms_std']:.2f} · MLP-4673 {MLP_L['rms_mean']:.2f} mrad (3 seeds)")
    d.image("Result ② 1 kHz control on the PYNQ-Z2", "fig15-tracking-pynq.png", [
        "• --sim RMS: PD 6.01 / model FF 0.17 / VQC 1.21 mrad",
        "• CAN loopback + virtual ESC: 6.31 / 0.38 / 1.45 (PL 1.38)",
        "• --sim jitter: VQC-PL p99 4.1 µs, VQC-PS 22.9 µs",
        "• Loopback mode exceeds 1 ms because the virtual ESC (Python) responds in about 960 µs",
    ], img_w=7000000)
    d.image("Result ③ HLS optimization", "fig14-hls-optimization.png", [
        "• v1 15,343 cycles (14.5 ns ❌)",
        "• v2–v3 register partitioning → II 15–27",
        "• v4 ping-pong → II=1, 2,643 cycles",
        "• v5 transcendental functions moved to PS → 2,248 cycles, LUT 29 %, DSP 33 %",
        f"• Bitstream WNS +{bit['wns_ns']} ns @100 MHz",
    ], img_w=7000000)
    d.table("Result ④ Measured inference paths (board, 20,000 runs)", [
        ["Path", "p50", "p99", "Max"],
        ["PL — C driver (preprocess + registers + core + tanh)", f"{t['pl_path_c']} µs", f"{t['pl_path_c_p99']} µs", f"{t['pl_path_c_max']} µs"],
        ["PS C kernel", f"{t['kernel_ps_c']} µs", f"{t['kernel_ps_c_p99']} µs", "48 ms (RT throttling)"],
        ["PL — one Python call", f"{t['policy_pl_python_p50']} µs", f"{t['policy_pl_python_p99']} µs", "—"],
        ["PS — one Python call", f"{t['policy_ps_python_p50']} µs", "141 µs", "—"],
        ["PL — pure Python MMIO", f"{t['pl_python_mmio_path_p50']} µs", "—", "—"],
    ], col_w=[0.52, 0.16, 0.16, 0.16], size=14, note="PL ↔ PS output difference: trained parameters 3.7e-7 (test vectors) / 3.9e-7 (500 random) — floating-point rounding level. 0 in a 20,000-run C bench with synthetic weights.")
    d.image("Time used within the 1 kHz period", "fig5-timing-budget.png")
    d.bullets("CAN path verification", [
        "• PS CAN0 enabled: device-tree overlay (status=okay), reference clock 8 → 100 MHz, SP 0.8 (same as Recoil)",
        "• Bitstream: CAN0 → EMIO → Pmod JA1 (TX, Y18) / JA2 (RX, Y19, pull-up)",
        "• Controller loopback: 5000/5000, Python round trip 236 µs",
        "• Two-process ping-pong: RTT p50 482 / p99 644 µs, 1.1 % loss",
        "• Normal mode, no transceiver: bit errors → bus-off = evidence the pin path is alive",
        "• Remaining: wire SN65HVD230 + 120 Ω, measure RTT, jitter and loss with the real ESC",
    ])
    d.image("Web visualization — VQC Actuator Lab (English site)", "fig16-site-hero.png", None,
            sub="three.js + Chart.js · real STL 3D models · in-browser 1 kHz simulator · D:\\robot\\website")
    d.image2("3D actuator assembled from the real part STLs", "fig17-site-actuator-exploded.png", "fig18-site-actuator-cutaway.png",
             ("Exploded view: housing · 16-pin ring · 15-lobe disc · eccentric shaft (1.25 mm) · output carrier · motor",
              "Cut-away: cycloidal disc (red) and output flange. Motor −15q, disc orbits + spins q"))
    d.image("Browser simulator — same results as the research code", "fig19-site-simulator.png", [
        "• JS ↔ Python policy output: VQC 1.4e-7, MLP 6.5e-8",
        "• Closed-loop RMS matches to 4 digits: PD 6.0093 · FF 0.1662 · VQC 1.2159 · MLP 0.8107 mrad",
        "• Figure: J 0.02, τc 0.3 N·m, 2 ms delay, two sines → VQC 1.29 mrad",
        "• 24-joint head-to-head: PD 6.85 · FF 0.78 · VQC 1.30 · MLP 1.04 mrad",
    ], img_w=7000000)
    d.image("Inside the VQC — live encoding angles and 64 states", "fig20-site-vqc.png")
    d.table("Main problems and fixes", [
        ["Problem", "Cause", "Action"],
        ["ESC SWD no response", "A part overheated during soldering (ESD guess rejected)", "❌ New board bought · replacement procedure written, connectors instead of soldering"],
        ["can0 not exposed", "DT status=disabled (the clock was present)", "Overlay + service"],
        ["Vivado blocked from running", "Smart App Control / 2026.1 mandatory license", "SAC off, installed 2024.1"],
        ["250 ms response lag", "Protocol without sequence numbers + stale reply taken as current", "Flush queue before each request, CAN filter"],
        ["HLS II 15–27", "In-place update, loop flattening", "Ping-pong arrays, LOOP_FLATTEN off"],
        ["Wrong answers on PL only", "HLS tanh/exp(double) — root cause unconfirmed", "Transcendental functions moved to PS"],
        ["Policy chatter", "τ_prev feedback", "Removed from the inputs"],
    ], col_w=[0.22, 0.42, 0.36], size=13)
    d.table("Next step — hardware test scenario (predicted, not measured)", [
        ["Step", "Content", "Prediction [basis]"],
        ["T1–T3", "Bus scan · info · calibration (set gear_ratio −15)", "Devices [1], 0 errors"],
        ["T4", "PDO round trip · 1 kHz jitter", "RTT 350–420 µs [calc.], jitter p99 < 20 µs"],
        ["T5", "PD 0.05 rad sine", "RMS 1.64 mrad (1.11–2.11) [sim]"],
        ["T6a/b", "Sine 0.2 rad 0.5 Hz / 0.3 rad 1 Hz", "VQC 0.67 / 2.21, MLP 0.60 / 1.41 mrad [sim]"],
        ["T6c", "Chirp 0.5→3.5 Hz (outside training range)", "VQC 12.3 vs MLP 3.2 mrad ⚠️ [sim]"],
        ["T8–T9", "System identification → retrain if out of range", "Estimate J, b, τc, R² > 0.9"],
    ], col_w=[0.12, 0.45, 0.43], size=13,
       note="actuator-vqc-control-report-scenario.md — 200 random joints, all values are predictions. Filling in the measured columns will make v3.0.")
    d.bullets("Conclusions", [
        "• **A 1 kHz FPGA control stack completed on real hardware**: CAN bitstream, Recoil driver, safety monitor, PL inference",
        "• **PL core**: 22.5 µs @100 MHz, path 29 µs, 2.2x vs PS, matches PS within ≤4e-7, jitter p99 4.1 µs (--sim)",
        f"• **The VQC policy works**: about 6x more accurate than PD only ({VQC_TXT} mrad)",
        f"• **But a same-size MLP (65) is {GAP}% more accurate** → the \"VQC parameter efficiency\" hypothesis is rejected for this task",
        "• This has nothing to do with quantum advantage. 6 qubits are fully simulable classically.",
    ])
    d.bullets("Limitations and next steps", [
        "• **Limitations**",
        (1, "Hardware runs are open loop only (no encoder), joint parameters are estimates, 1 kHz real bus not measured"),
        (1, "Root cause of PL wrong answers unconfirmed, qubit/layer sweep not done"),
        "• **Next steps**",
        (1, "1) Replace the ESC with the new board (bought) → BOARD_REPLACEMENT.md: check SWD before soldering → firmware → wiring and 60 Ω check → recoil_cli.py scan / info / calibrate"),
        (1, "2) Wire the transceiver → start with run_controller.py --policy pd --amp 0.05"),
        (1, "3) System identification from hardware logs → retrain → VQC · MLP · model FF hardware comparison"),
        (1, "4) Measure real-bus RTT · jitter · loss → re-evaluate G2"),
        "• Code and how to reproduce: D:\\robot\\pynq-can\\README.md · raw data: docs/results/",
    ])
    d.save("actuator-vqc-control-report.pptx")


def guide_deck():
    d = Deck()
    d.title("A Guide for Complete Beginners\nWhat Does It Mean to Control a Robot Joint with a Quantum Circuit?",
            "v2.0 — rewritten from what we actually built and measured", "2026-10-06")
    d.bullets("30-second summary", [
        "• A robot joint must decide \"how much force to apply\" 1,000 times a second.",
        "• We computed part of that with quantum-circuit math (a VQC, 72 numbers), and ran that computation on an FPGA chip.",
        f"• ① The VQC was useful: its error was about 6x smaller than basic control ({VQC_TXT} mrad).",
        f"• ② But a small neural network with 65 numbers was {GAP}% more accurate.",
        "• ③ The FPGA was 2.2x faster than the CPU (29 µs vs 65 µs), with practically the same answers.",
        "• Not done yet: closed-loop control of the real joint (the motor moved open-loop on 10-13, but there is no angle sensor)",
    ])
    d.image("What we built", "fig1-system-architecture.png")
    d.table("The cast — 4 pieces of hardware", [
        ["Hardware", "What it is", "What it does"],
        ["MAD 5010 motor", "Drone BLDC motor", "Torque (Kt 0.1176 N·m/A)"],
        ["15:1 cycloidal", "Reducer", "Lowers speed, raises torque"],
        ["B-G431B-ESC1", "Motor controller (STM32)", "Current 10,000x/s, position 2,000x/s"],
        ["PYNQ-Z2", "CPU + FPGA board", "Target generation, VQC compute, CAN comms"],
    ], col_w=[0.25, 0.3, 0.45], size=16)
    d.image("Control is split into 4 layers", "fig13-control-layers.png")
    d.image("Why a reducer?", "fig12-gearbox.png")
    d.image("Bits and qubits", "fig10-bit-vs-qubit.png")
    d.image("The VQC — 72 dials", "fig2-vqc-circuit.png", [
        "• 6 qubits → handles 64 numbers",
        "• Dials (learned numbers) = 6 × 3 × 4 = 72",
        "• Joint state turned into angles and fed in again at every layer",
        "• Final measurement → \"how much extra push\"",
    ], img_w=7000000)
    d.image("How many numbers: neural network vs VQC", "fig11-params-structure.png", [
        "• Large neural network: 4,673–4,801",
        "• Small neural network: 65 ← added in v2.0",
        "• VQC: 72",
        "• A fair comparison is between similar sizes!",
    ], img_w=7000000)
    d.image("What actually happened", "fig7-timeline.png")
    d.table("Problems we hit — 6 examples", [
        ["Problem", "In plain words", "Outcome"],
        ["Motor controller broke", "A part overheated during soldering", "❌ New board bought, replacement procedure ready"],
        ["Windows blocked tools", "A security feature blocked the FPGA tools", "Turned it off"],
        ["Mixed-up replies", "Read an old reply as the current one", "Empty the inbox first"],
        ["FPGA was slow", "Waited to read and write the same slot", "Separate read and write slots"],
        ["Wrong only on the chip", "Simulation right, real chip wrong", "Do that math on the CPU"],
        ["Policy chattered", "Its own output fed back as input", "Removed that input"],
    ], col_w=[0.25, 0.45, 0.3], size=15)
    d.image("Result ① The VQC was useful", "fig15-tracking-pynq.png", [
        "• Run at 1 kHz on the board",
        "• PD only: 6.01 mrad",
        "• PD + VQC: 1.21 mrad (5x better)",
        "• PD + physics formula: 0.17 mrad",
        "• 1 mrad ≈ 0.057°",
    ], img_w=7000000)
    d.image("Result ② But a small neural network was more accurate", "fig3-vqc-vs-mlp.png", None,
            sub=f"VQC (72) {VQC['rms_mean']:.2f} mrad vs small neural network (65) {MLP_S['rms_mean']:.2f} mrad — v1.0's \"66.7x fewer\" was an unfair comparison")
    d.image("Result ③ The FPGA was fast and steady", "fig14-hls-optimization.png", [
        "• Five revisions: 15,343 → 2,248 clocks",
        "• FPGA path 29.0 µs (top 1% still 29.8 µs)",
        "• CPU 64.6 µs",
        "• Practically the same answers as the CPU (difference ≤ 4×10⁻⁷)",
        "• 1 kHz control timing wobble, top 1%: 4.1 µs",
    ], img_w=7000000)
    d.image("See for yourself — VQC Actuator Lab website", "fig16-site-hero.png", None,
            sub="D:\\robot\\website → python -m http.server 8765 → http://127.0.0.1:8765/ (English)")
    d.image2("3D actuator built from the real parts", "fig17-site-actuator-exploded.png", "fig18-site-actuator-cutaway.png",
             ("Pull it apart with the Explode slider", "Cut it open with Cut-away — the red part is the cycloidal disc"))
    d.image2("Try control in the browser", "fig19-site-simulator.png", "fig20-site-vqc.png",
             ("1 kHz control while changing policy · trajectory · mass · friction · delay", "Qubit angles and the 64 state probabilities change live"))
    d.bullets("The most important part — why this is not \"quantum advantage\"", [
        "• ① It is not a real quantum computer. We only computed the math on an ordinary chip.",
        "• ② 6 qubits (64 numbers) is small enough for a smartphone to compute instantly.",
        "• ③ In a fair comparison, a neural network of the same size did better.",
        "• → It is right to see the VQC as \"a math function of a particular shape\".",
        "• Reporting results that differ from expectations as they are is good research.",
    ])
    d.bullets("Limitations and what's next", [
        "• Limitations: real motor driven open-loop only (no encoder) · joint values estimated · 1 kHz real CAN bus not measured · cause of FPGA wrong answers unconfirmed",
        "• Next",
        (1, "1) Replace with the new motor-controller board — check before soldering → firmware → wiring, connect with connectors"),
        (1, "2) Connect the communication part (transceiver) → find the device → calibrate"),
        (1, "3) Real tests starting with small motions → real comparison of VQC · neural network · physics formula"),
        "• Software and FPGA circuit are ready — we can start as soon as the board is alive",
    ])
    d.table("A few terms", [
        ["Term", "Meaning"],
        ["Feed-forward", "Force added in advance, before an error appears"],
        ["Residual structure", "A learned policy only adds corrections on top of basic control"],
        ["Jitter", "How uneven the period is"],
        ["HLS", "A tool that turns C code into an FPGA circuit"],
        ["mrad", "Milliradian (1 mrad ≈ 0.057°)"],
        ["Domain randomization", "Training under randomly varied conditions to be robust to real-world differences"],
    ], col_w=[0.25, 0.75], size=16)
    d.save("guide-for-beginners.pptx")


if __name__ == "__main__":
    report_deck()
    guide_deck()
