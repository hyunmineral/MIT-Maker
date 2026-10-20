"""Export the first real-hardware run (2026-10-13, open loop, PYNQ -> CANable -> ESC) for the website.

    python website/tools/export_hw_log.py

Reads docs/results/logs/openloop_pynq_2026-10-13.csv (200 Hz, 4,000 rows) and writes
website/data/hw_openloop.json, decimated to 100 Hz. Angles are COMMANDS (no encoder fitted).
"""
import csv
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "docs", "results", "logs", "openloop_pynq_2026-10-13.csv")
OUT = os.path.join(ROOT, "website", "data", "hw_openloop.json")

rows = list(csv.DictReader(open(SRC, newline="")))
keep = rows[::2]
data = {
    "source": "docs/results/logs/openloop_pynq_2026-10-13.csv (decimated 200 Hz -> 100 Hz)",
    "note": "open-loop drive, no encoder: angles are commanded / applied by the firmware, not measured",
    "t": [round(float(r["t"]), 3) for r in keep],
    "q_cmd": [round(float(r["q_cmd_out"]), 5) for r in keep],
    "q_applied": [round(float(r["q_applied_out"]), 5) for r in keep],
    "voltage": [round(float(r["voltage"]), 4) for r in keep],
    "i_phase": [round(float(r["i_phase"]), 4) for r in keep],
}
json.dump(data, open(OUT, "w"), separators=(",", ":"))
print(f"wrote {os.path.relpath(OUT, ROOT)}: {len(keep)} points of {len(rows)}")
