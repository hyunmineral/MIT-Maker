"""Replace the Korean font name that python-docx/python-pptx default themes carry for the Hangul script
("Malgun Gothic" written in Korean) with its English name, so the generated files contain no Hangul.

    from office_clean import clean_theme_fonts; clean_theme_fonts(path)
    python docs/tools/office_clean.py file.docx [file.pptx ...]
"""
import os
import shutil
import sys
import tempfile
import zipfile

# the Korean name of Malgun Gothic, built from code points so this source file stays ASCII
KOREAN_MALGUN = "".join(map(chr, (0xB9D1, 0xC740, 0x20, 0xACE0, 0xB515)))


def clean_theme_fonts(path):
    with zipfile.ZipFile(path) as zin:
        items = [(i, zin.read(i.filename)) for i in zin.infolist()]
    changed = False
    out = []
    for info, data in items:
        if info.filename.endswith(".xml") and "theme" in info.filename:
            text = data.decode("utf-8")
            if KOREAN_MALGUN in text:
                data = text.replace(KOREAN_MALGUN, "Malgun Gothic").encode("utf-8")
                changed = True
        out.append((info, data))
    if not changed:
        return False
    fd, tmp = tempfile.mkstemp(suffix=os.path.splitext(path)[1], dir=os.path.dirname(path))
    os.close(fd)
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for info, data in out:
            zout.writestr(info, data)
    shutil.move(tmp, path)
    return True


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(p, "cleaned" if clean_theme_fonts(p) else "unchanged")
