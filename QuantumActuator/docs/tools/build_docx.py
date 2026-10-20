"""Render the docs/*.md files to .docx (python-docx), keeping headings, tables,
code blocks, quotes, lists and figures.

    python docs/tools/build_docx.py            # all three documents
    python docs/tools/build_docx.py report     # one of: report, scenario, paper, guide, replacement, move
"""
import os
import re
import sys

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

from QuantumActuator.docs.tools.office_clean import clean_theme_fonts

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
FONT = "Calibri"
MONO = "Consolas"
TARGETS = {"report": "actuator-vqc-control-report", "scenario": "actuator-vqc-control-report-scenario",
           "paper": "paper-vqc-actuator", "guide": "guide-for-beginners",
           "replacement": "besc1-firmware-bringup/BOARD_REPLACEMENT",
           "move": "besc1-firmware-bringup/MOVE_WITHOUT_CAN"}
INLINE = re.compile(r"(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*)")


def set_font(run, name=FONT, size=None, bold=None, color=None, italic=None):
    run.font.name = name
    run._element.rPr.rFonts.set(qn("w:eastAsia"), name)
    if size:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if italic is not None:
        run.italic = italic
    if color:
        run.font.color.rgb = RGBColor.from_string(color)


def shade(cell_or_par, hex_fill):
    el = cell_or_par._tc if hasattr(cell_or_par, "_tc") else cell_or_par._p
    pr = el.get_or_add_tcPr() if hasattr(cell_or_par, "_tc") else el.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_fill)
    pr.append(shd)


def add_inline(par, text, size=10.5, base_bold=False):
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            set_font(par.add_run(part[2:-2]), size=size, bold=True)
        elif part.startswith("`") and part.endswith("`"):
            set_font(par.add_run(part[1:-1]), name=MONO, size=size - 1, color="8B1A1A")
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            set_font(par.add_run(part[1:-1]), size=size, italic=True, bold=base_bold)
        else:
            set_font(par.add_run(part), size=size, bold=base_bold)


def strip_links(text):
    return re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)


def add_table(doc, rows):
    cells = [[c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", r.strip().strip("|"))] for r in rows]
    header, body = cells[0], [r for r in cells[2:]]
    ncol = len(header)
    t = doc.add_table(rows=1 + len(body), cols=ncol)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for j, h in enumerate(header):
        c = t.rows[0].cells[j]
        c.text = ""
        add_inline(c.paragraphs[0], strip_links(h), size=9, base_bold=True)
        shade(c, "DCE6F2")
    for i, r in enumerate(body, start=1):
        for j in range(ncol):
            c = t.rows[i].cells[j]
            c.text = ""
            add_inline(c.paragraphs[0], strip_links(r[j] if j < len(r) else ""), size=9)
    doc.add_paragraph()


def build(md_path, out_path):
    doc = Document()
    sec = doc.sections[0]
    sec.left_margin = sec.right_margin = Cm(2.2)
    sec.top_margin = sec.bottom_margin = Cm(2.0)
    st = doc.styles["Normal"]
    st.font.name = FONT
    st.element.rPr.rFonts.set(qn("w:eastAsia"), FONT)
    st.font.size = Pt(10.5)

    lines = open(md_path, encoding="utf-8").read().splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("```"):
            buf = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            p = doc.add_paragraph()
            shade(p, "F3F3F3")
            for k, b in enumerate(buf):
                r = p.add_run(b)
                set_font(r, name=MONO, size=8.5)
                if k < len(buf) - 1:
                    r.add_break()
            i += 1
            continue
        if s.startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|?\s*:?-{2,}", lines[i + 1]):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(lines[i])
                i += 1
            add_table(doc, rows)
            continue
        m = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)", s)
        if m:
            img = os.path.join(os.path.dirname(md_path), m.group(2))
            if os.path.exists(img):
                doc.add_picture(img, width=Cm(16))
                doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
            i += 1
            continue
        m = re.match(r"^(#{1,4})\s+(.*)", s)
        if m:
            level = len(m.group(1))
            h = doc.add_heading(level=min(level, 3) if level > 1 else 0 if i == 0 else 1)
            add_inline(h, strip_links(m.group(2)), size={1: 18, 2: 15, 3: 12.5, 4: 11.5}[level], base_bold=True)
            i += 1
            continue
        if s.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip()[1:].strip())
                i += 1
            p = doc.add_paragraph()
            shade(p, "FFF8E1")
            p.paragraph_format.left_indent = Cm(0.5)
            for k, b in enumerate(buf):
                if not b:
                    continue
                add_inline(p, strip_links(b), size=9.5)
                if k < len(buf) - 1:
                    p.add_run().add_break()
            continue
        if s in ("---", "***"):
            i += 1
            continue
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", line)
        if m:
            indent = len(m.group(1)) // 2
            style = "List Number" if m.group(2)[0].isdigit() else "List Bullet"
            p = doc.add_paragraph(style=style if indent == 0 else style + " 2")
            add_inline(p, strip_links(m.group(3)))
            i += 1
            continue
        if not s:
            i += 1
            continue
        buf = [s]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#|\||>|```|!\[|\s*[-*]\s|\s*\d+\.\s|---)", lines[i].strip()):
            buf.append(lines[i].strip())
            i += 1
        text = " ".join(buf).replace("\\*", "*")
        p = doc.add_paragraph()
        # centered figure caption: "**Figure N." (English) or the Korean caption form (snapshot in docs/ko)
        if re.match(r"^\*\*(?:Figure|\uADF8\uB9BC) \d+", text):
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            add_inline(p, strip_links(text), size=9.5)
        else:
            add_inline(p, strip_links(text))
    doc.save(out_path)
    clean_theme_fonts(out_path)
    print("wrote", os.path.relpath(out_path, DOCS))


if __name__ == "__main__":
    keys = sys.argv[1:] or list(TARGETS)
    for k in keys:
        name = TARGETS[k]
        build(os.path.join(DOCS, name + ".md"), os.path.join(DOCS, name + ".docx"))
