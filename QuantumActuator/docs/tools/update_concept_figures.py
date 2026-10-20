"""Re-render the six hand-made conceptual SVG figures to PNG (2x) with headless Chrome.

    python docs/tools/update_concept_figures.py

History: earlier versions of this script applied find/replace edits to the Korean SVGs
(correcting assumed numbers to measured ones: fig2 PL core 22.5 µs, fig8 root cause,
fig11 caption, fig12 efficiency 0.85 -> 15.0 N·m / 12.75x, fig13 1 kHz and 22.5/29 µs).
That Korean edit history is preserved in docs/ko. The SVGs are now English and already
contain the corrected values, so EDITS is empty and the script only re-renders
docs/figures/svg/<name>.svg -> docs/figures/png/<name>.png.
"""
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
FIG = os.path.join(os.path.dirname(HERE), "figures")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

NAMES = ["fig2-vqc-circuit", "fig8-diagnosis-flow", "fig10-bit-vs-qubit",
         "fig11-params-structure", "fig12-gearbox", "fig13-control-layers"]

# name -> [(old, new), ...]; applied before rendering. Intentionally empty (see docstring).
EDITS = {}


def size(svg):
    m = re.search(r'width="(\d+)" height="(\d+)"', svg)
    return int(m.group(1)), int(m.group(2))


for name in NAMES:
    path = os.path.join(FIG, "svg", name + ".svg")
    s = open(path, encoding="utf-8").read()
    edits = EDITS.get(name, [])
    if edits:
        for a, b in edits:        # pairs may chain old -> intermediate -> new wording
            if a in s:
                s = s.replace(a, b)
        stale = [a for a, b in edits if a in s]
        if stale:
            raise SystemExit(f"{name}: stale text left: {stale}")
        open(path, "w", encoding="utf-8", newline="\n").write(s)
    w, h = size(s)
    out = os.path.join(FIG, "png", name + ".png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={w},{h}",
                    "--force-device-scale-factor=2", f"--screenshot={out}", "file:///" + path.replace("\\", "/")],
                   check=True, capture_output=True, timeout=120)
    print("rendered", name, w, h)
