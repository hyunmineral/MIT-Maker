"""Collect the final deliverables (docx, pptx, figures, raw data) into one folder.

    python docs/tools/package_final.py [out_dir]

Default out_dir: D:/robot/final_report_<YYYY-MM-DD>. The source of truth stays in docs/;
the folder is a copy for hand-off. Every .md is rebuilt to .docx before copying.
All content is English (the Korean edition was archived on 2026-10-17, see archive_korean.py).
"""
import datetime
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
ROOT = os.path.dirname(DOCS)

MAIN = [  # (source docx relative to docs/, file name in the package)
    ("actuator-vqc-control-report.docx", "01_Development_Report.docx"),
    ("paper-vqc-actuator.docx", "02_Paper.docx"),
    ("guide-for-beginners.docx", "03_Beginners_Guide.docx"),
    ("actuator-vqc-control-report-scenario.docx", "04_Test_Scenario_Predictions.docx"),
]
SUPPORT = [
    ("besc1-firmware-bringup/BOARD_REPLACEMENT.docx", "05_ESC_Board_Replacement.docx"),
    ("besc1-firmware-bringup/MOVE_WITHOUT_CAN.docx", "06_Moving_Without_Encoder.docx"),
]
SLIDES = [
    ("actuator-vqc-control-report.pptx", "Slides_Development_Report.pptx"),
    ("guide-for-beginners.pptx", "Slides_Beginners_Guide.pptx"),
]

INDEX = """# Final Report Package — Actuator Control with a VQC Policy ({date})

Final documents of the project that accelerates a variational quantum circuit (VQC) policy on a
PYNQ-Z2 FPGA for one Berkeley Humanoid Lite joint (MAD 5010 + 15:1 cycloidal reducer,
B-G431B-ESC1 with Recoil firmware).

## Documents

| File | Contents |
|---|---|
| `01_Development_Report.docx` | Development report v2.4: all results, 24 troubleshooting items, goal assessment, open-loop real-hardware run (§4.9) |
| `02_Paper.docx` | The same results as a paper, v2.2 (general-audience style; real-hardware run in Section 4.6) |
| `03_Beginners_Guide.docx` | Explanation for complete beginners, v2.4 (19 problems, 9.19 first real-hardware run) |
| `04_Test_Scenario_Predictions.docx` | Closed-loop real-hardware test procedure T0–T9 with **predicted values** (not measurements) |
| `05_ESC_Board_Replacement.docx` | 12-step ESC replacement procedure and the 2026-10-13 work log |
| `06_Moving_Without_Encoder.docx` | Moving the actuator without an encoder: demo and open-loop firmware, real-hardware results |
| `slides/` | Two slide decks (pptx) |
| `figures/png`, `figures/svg` | Figures used in the documents (fig1–24; website screenshots fig16–24) |
| `data/` | Raw data: `results.json`, experiment logs (including the first real run `logs/openloop_pynq_2026-10-13.csv`), scenario predictions |
| `markdown/` | Markdown sources of the documents above (with figures; readable as-is) |
| `video/vqc_actuator_lab_tour.mp4` | 2:51 guided tour of the project website (1600×900, H.264), recorded from the live site |

## Key results (all measured)

- Simulation (256 randomized joints): PD only 8.79, model FF 1.55, **VQC 1.43 ± 0.07**, same-size MLP (65 params) **0.98 ± 0.01** mrad
  → the hypothesis "a VQC is more parameter-efficient than an MLP" is **rejected**
- FPGA: VQC core 22.5 µs @ 100 MHz, PL path 29.0 µs (2.2x faster than PS 64.6 µs), 1 kHz loop jitter p99 4.1 µs (`--sim`)
- Real hardware (2026-10-13, new ESC): open-loop drive PYNQ → CANable → ESC, 4,000 commands with 0 missed replies,
  RTT p50 1.81 ms, output-shaft motion confirmed visually

## Limitations

- No encoder (AS5600) was fitted, so **closed-loop real-hardware control and a real-hardware VQC comparison were not done**.
  Control performance figures come from simulation and the emulator.
- The CANable (USB) path is too slow for 1 kHz, and the PS CAN + SN65HVD230 path needed for 1 kHz is unresolved.

Sources and regeneration tools: `D:\\robot\\docs` (build: `python docs/tools/package_final.py`).
"""


def _copy_items(base, items, dest, copied, prefix):
    os.makedirs(dest, exist_ok=True)
    for src, name in items:
        shutil.copy2(os.path.join(base, src), os.path.join(dest, name))
        copied.append(os.path.join(prefix, name))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, f"final_report_{datetime.date.today():%Y-%m-%d}")
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    subprocess.run([sys.executable, os.path.join(HERE, "build_docx.py")], check=True, env=env)
    subprocess.run([sys.executable, os.path.join(HERE, "build_pptx.py")], check=True, env=env)

    os.makedirs(out, exist_ok=True)
    for entry in os.listdir(out):   # empty it in place (the folder itself may be open in Explorer/a shell)
        p = os.path.join(out, entry)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)

    copied = []
    _copy_items(DOCS, MAIN + SUPPORT, out, copied, "")
    _copy_items(DOCS, SLIDES, os.path.join(out, "slides"), copied, "slides")

    # figures (png for viewing, svg sources), raw data
    shutil.copytree(os.path.join(DOCS, "figures", "png"), os.path.join(out, "figures", "png"))
    shutil.copytree(os.path.join(DOCS, "figures", "svg"), os.path.join(out, "figures", "svg"))
    shutil.copytree(os.path.join(DOCS, "results"), os.path.join(out, "data"))
    # markdown sources next to the docx, so the package can be rebuilt or diffed
    md = os.path.join(out, "markdown")
    os.makedirs(os.path.join(md, "besc1-firmware-bringup"))
    for name in ("actuator-vqc-control-report.md", "paper-vqc-actuator.md", "guide-for-beginners.md",
                 "actuator-vqc-control-report-scenario.md", "README.md"):
        shutil.copy2(os.path.join(DOCS, name), md)
    for name in ("README.md", "CAN_SETUP.md", "BOARD_REPLACEMENT.md", "MOVE_WITHOUT_CAN.md"):
        shutil.copy2(os.path.join(DOCS, "besc1-firmware-bringup", name), os.path.join(md, "besc1-firmware-bringup"))
    # md files reference figures/png/... relative to docs/: make that work inside markdown/ too
    shutil.copytree(os.path.join(DOCS, "figures"), os.path.join(md, "figures"))

    # website tour video (website/tools/record_tour.py), if recorded
    video = os.path.join(ROOT, "website", "video", "vqc_actuator_lab_tour.mp4")
    if os.path.exists(video):
        os.makedirs(os.path.join(out, "video"))
        shutil.copy2(video, os.path.join(out, "video"))
        copied.append(os.path.join("video", os.path.basename(video)))

    with open(os.path.join(out, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(INDEX.format(date=f"{datetime.date.today():%Y-%m-%d}"))

    n_png = len(os.listdir(os.path.join(out, "figures", "png")))
    print(f"package: {out}")
    for c in copied:
        print("  ", c)
    print(f"   figures/png: {n_png} files, figures/svg, data/, markdown/")


if __name__ == "__main__":
    main()
