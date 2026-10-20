"""Structural + stale-phrase check over the release documents.

    python docs/tools/check_docs.py
"""
import io
import os
import re

DOCS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ["actuator-vqc-control-report.md", "paper-vqc-actuator.md", "guide-for-beginners.md",
         "actuator-vqc-control-report-scenario.md", "README.md"] + \
        ["besc1-firmware-bringup/" + f for f in ("README.md", "CAN_SETUP.md", "BOARD_REPLACEMENT.md", "MOVE_WITHOUT_CAN.md")]
STALE = ["polarity unverified", "12.3 N·m", "2,6xx", "never driven", "must be replaced", "18 problems",
         "more than 8x", "not yet performed with the new board"]
HANGUL = re.compile("[" + chr(0xAC00) + "-" + chr(0xD7A3) + "]")   # the documents must contain no Hangul (written as escapes)
CELL = re.compile(r"(?<!\\)\|")

problems = 0
for f in FILES:
    lines = io.open(os.path.join(DOCS, f), encoding="utf-8").read().split("\n")
    if sum(1 for l in lines if l.strip().startswith("```")) % 2:
        print(f, "odd number of code fences"); problems += 1
    in_fence, i = False, 0
    while i < len(lines):
        if lines[i].strip().startswith("```"):
            in_fence = not in_fence
        if (not in_fence and lines[i].strip().startswith("|") and i + 1 < len(lines)
                and re.match(r"^\s*\|?\s*:?-{2,}", lines[i + 1])):
            n = len(CELL.split(lines[i].strip().strip("|")))
            j = i
            while j < len(lines) and lines[j].strip().startswith("|"):
                m = len(CELL.split(lines[j].strip().strip("|")))
                if m != n:
                    print(f, "table columns", j + 1, m, "!=", n); problems += 1
                j += 1
            i = j
            continue
        i += 1
    base = os.path.join(DOCS, os.path.dirname(f))
    for m in re.finditer(r"!\[[^\]]*\]\(([^)]+)\)", "\n".join(lines)):
        if not os.path.exists(os.path.join(base, m.group(1))):
            print(f, "missing image", m.group(1)); problems += 1
    for k, l in enumerate(lines, 1):
        if HANGUL.search(l):
            print(f"{f}:{k} Hangul: {l[:120]}"); problems += 1
        for w in STALE:
            if w in l:
                print(f"{f}:{k} stale? [{w}] {l[:150]}")
print("problems (structure):", problems)
