#!/usr/bin/env python3
"""Generates the RobotForElders app icon.

Renders the `FaceStyle` presets exactly as the app draws them.
Eye and mouth coordinates are the values from Sources/DesignSystem/FaceStyle.swift, and the corner radii are
the result after applying the CSS scaling rule (f scaling) from CSSShapes.swift.

    happy.eye   FacePart(120, 60, .top(120), borderTop: 22)
                → f = 0.5 → top radius 60 · outer semicircle − inner semi-ellipse = ∩
    happy.mouth FacePart.solid(170, 80, .bottom(200))
                → f = 0.4 → bottom radius 80 · a U with a flat top
    neutral.eye FacePart.solid(110, 110, .all(55))      → circle
    neutral.mouth FacePart.solid(120, 22, .all(999))    → f = 0.011 → capsule

The background is the Backdrop.session colour (#1B2029 → #0C0E13). Since this is an icon, not a screen,
only the glow centre is moved behind the face.

Usage: python3 make_icon.py <variant> <output path>
"""

import math
import sys
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # mask supersampling factor
INNER = (0x1B, 0x20, 0x29)  # Backdrop.session inner
OUTER = (0x0C, 0x0E, 0x13)  # Backdrop.session outer
CREAM = (0xF2, 0xEB, 0xDC)  # Theme.cream
BLUE = (0x28, 0x64, 0xF0)   # Theme.blue

STACK_GAP = 34.0            # RobotFaceView's VStack(spacing: 34)

# ── Variants ──────────────────────────────────────────────────────────
# `eye_border` is an optical correction for the icon. Using the app's 22 as is, at 60pt on the home screen
# the stroke smudges to 2.2px and **the eyes vanish, leaving only the mouth.** An icon shouldn't be a shrunken screen
# but something redrawn to give the same impression at a small size.
VARIANTS = {
    # Smiling face — ∩ eyes + open mouth. The thick stroke (34) keeps the eyes visible even at 60pt.
    "happy": dict(kind="arch", eye_w=120, eye_h=60, eye_border=34, eye_gap=140,
                  mouth_w=170, mouth_h=80, mouth_kind="ubowl", fill=0.76),
    # Smiling face · thin eyes — close to the app original (22). Gentle eyes, but weak at small sizes.
    "happy-thin": dict(kind="arch", eye_w=120, eye_h=60, eye_border=26, eye_gap=140,
                       mouth_w=170, mouth_h=80, mouth_kind="ubowl", fill=0.80),
    # Default face — solid round eyes + straight mouth. The crispest and most robot-like.
    "neutral": dict(kind="disc", eye_w=110, eye_h=110, eye_border=0, eye_gap=140,
                    mouth_w=120, mouth_h=22, mouth_kind="capsule", fill=0.70),
}


def arc(cx, cy, rx, ry, a0, a1, n=240):
    return [(cx + rx * math.cos(a0 + (a1 - a0) * i / n),
             cy + ry * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def eye_shapes(v, x):
    """(shape to fill, shape to cut out) — if there's nothing to cut out, the second is None."""
    w, h = v["eye_w"], v["eye_h"]
    if v["kind"] == "disc":
        cx, cy = x + w / 2, h / 2
        return arc(cx, cy, w / 2, h / 2, 0, 2 * math.pi), None
    # arch: semicircle − semi-ellipse sharing a baseline
    cx, cy = x + w / 2, h
    outer = arc(cx, cy, w / 2, h, math.pi, 2 * math.pi)
    inner = arc(cx, cy, w / 2, h - v["eye_border"], math.pi, 2 * math.pi)
    return outer, inner


def mouth_shape(v, x, y):
    w, h = v["mouth_w"], v["mouth_h"]
    if v["mouth_kind"] == "capsule":
        r = h / 2
        pts = arc(x + w - r, y + r, r, r, -math.pi / 2, math.pi / 2, 120)
        pts += arc(x + r, y + r, r, r, math.pi / 2, 3 * math.pi / 2, 120)
        return pts
    # ubowl: flat top with bottom corner radius 80 (after applying CSS f scaling)
    r = 80.0
    pts = [(x, y), (x + w, y)]
    pts += arc(x + w - r, y, r, r, 0, math.pi / 2, 120)
    pts += arc(x + r, y, r, r, math.pi / 2, math.pi, 120)
    return pts


def face_size(v):
    return (v["eye_w"] * 2 + v["eye_gap"],
            v["eye_h"] + STACK_GAP + v["mouth_h"])


def build_face_mask(v, scale, ox, oy):
    big = SIZE * SS
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    fw, _ = face_size(v)

    def T(pts):
        return [((ox + px * scale) * SS, (oy + py * scale) * SS) for px, py in pts]

    for i in range(2):
        outer, inner = eye_shapes(v, i * (v["eye_w"] + v["eye_gap"]))
        d.polygon(T(outer), fill=255)
        if inner:
            d.polygon(T(inner), fill=0)

    mx = (fw - v["mouth_w"]) / 2
    my = v["eye_h"] + STACK_GAP
    d.polygon(T(mouth_shape(v, mx, my)), fill=255)

    return mask.resize((SIZE, SIZE), Image.LANCZOS)


def build_background(glow_cy):
    bg = Image.new("RGB", (SIZE, SIZE))
    px = bg.load()
    rx, ry = SIZE * 1.20, SIZE * 0.90
    cx, cy = SIZE * 0.5, SIZE * 0.42   # behind the face, not at the screen position (0.15)
    stop = 0.62
    for y in range(SIZE):
        dy = (y - cy) / ry
        for x in range(SIZE):
            t = min(1.0, math.hypot((x - cx) / rx, dy) / stop)
            px[x, y] = (int(INNER[0] + (OUTER[0] - INNER[0]) * t),
                        int(INNER[1] + (OUTER[1] - INNER[1]) * t),
                        int(INNER[2] + (OUTER[2] - INNER[2]) * t))

    # BreathingGlow approximation — a soft blue light behind the face
    glow = Image.new("L", (SIZE, SIZE), 0)
    gp = glow.load()
    radius = SIZE * 0.42
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x - SIZE / 2, y - glow_cy) / radius
            if d < 1.0:
                gp[x, y] = int(255 * 0.24 * (1.0 - d) ** 2)
    glow = glow.filter(ImageFilter.GaussianBlur(SIZE * 0.02))
    bg.paste(Image.new("RGB", (SIZE, SIZE), BLUE), (0, 0), glow)
    return bg


def render(name, out):
    v = VARIANTS[name]
    fw, fh = face_size(v)
    scale = (SIZE * v["fill"]) / fw
    w, h = fw * scale, fh * scale
    ox = (SIZE - w) / 2
    oy = (SIZE - h) / 2 - SIZE * 0.015   # slightly above dead centre looks more stable

    icon = build_background(oy + h * 0.45)
    icon.paste(Image.new("RGB", (SIZE, SIZE), CREAM), (0, 0),
               build_face_mask(v, scale, ox, oy))
    icon.save(out, "PNG")
    print(f"{name:12s} → {out}")


if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2])
