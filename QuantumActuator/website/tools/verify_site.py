"""Open the site in headless Chrome, check for errors, verify the JS models against
the Python reference, and (with --shots) capture section screenshots.

    python website/tools/verify_site.py [--url http://127.0.0.1:8765] [--shots]
"""
import argparse
import json
import os
import sys

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
SHOT_DIR = os.path.join(os.path.dirname(HERE), "img")
ARGS = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8765/")
    ap.add_argument("--shots", action="store_true")
    a = ap.parse_args()
    errors = []
    with sync_playwright() as pw:
        b = pw.chromium.launch(channel="chrome", headless=True, args=ARGS)
        page = b.new_page(viewport={"width": 1600, "height": 960}, device_scale_factor=1)
        page.on("console", lambda m: errors.append(f"console.{m.type}: {m.text}") if m.type in ("error", "warning") else None)
        page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
        page.goto(a.url, wait_until="networkidle")
        page.wait_for_function("document.body.dataset.ready === '1' && window.VQCLab && window.VQCLab.ready()", timeout=60000)
        pc = page.evaluate("VQCLab.policyCheck()")
        lc = page.evaluate("VQCLab.loopCheck()")
        print("policy max |JS - Python|:", json.dumps(pc))
        print("closed loop RMS [mrad] JS vs Python:", {k: (round(v["js"], 4), round(v["py"], 4)) for k, v in lc.items()})
        ok = max(pc.values()) < 1e-5 and all(abs(v["js"] - v["py"]) < 1e-3 for v in lc.values())
        hw = page.evaluate("window.__hw")
        print("hardware section:", hw)
        ok = ok and hw is not None and hw["points"] == 2000
        if a.shots:
            os.makedirs(SHOT_DIR, exist_ok=True)
            shoot(page)
        b.close()
    print("console/page errors:", errors or "none")
    print("VERIFY", "OK" if ok and not [e for e in errors if "error" in e] else "FAIL")
    return 0 if ok else 1


def shoot(page):
    page.wait_for_timeout(2500)
    page.screenshot(path=os.path.join(SHOT_DIR, "site-hero.png"))
    # section screenshots: hide the fixed top navigation so it does not cover section headings
    page.add_style_tag(content=".topnav{display:none !important}")
    # actuator: exploded + cut-away
    page.evaluate("document.getElementById('actuator').scrollIntoView()")
    page.evaluate("""() => { const s = document.getElementById('spin'); s.checked = false; s.dispatchEvent(new Event('change'));
        const e = document.getElementById('explode'); e.value = 1; e.dispatchEvent(new Event('input'));
        const q = document.getElementById('manualQ'); q.value = 0.6; q.dispatchEvent(new Event('input')); }""")
    page.wait_for_timeout(2500)
    page.locator("#actuator").screenshot(path=os.path.join(SHOT_DIR, "site-actuator-exploded.png"))
    page.evaluate("""() => { const e = document.getElementById('explode'); e.value = 0; e.dispatchEvent(new Event('input'));
        const v = VQCLab.views.act; v.explode = 0; v.explodeTarget = 0;
        v.camera.position.set(95, 125, 85); v.controls.target.set(0, 0, -20);
        const c = document.getElementById('cutaway'); c.checked = true; c.dispatchEvent(new Event('change')); }""")
    page.wait_for_timeout(2000)
    page.locator("#act3d").screenshot(path=os.path.join(SHOT_DIR, "site-actuator-cutaway.png"))
    page.locator("#system").screenshot(path=os.path.join(SHOT_DIR, "site-system.png"))
    # simulator: VQC on a randomised plant, let it run 6 s
    page.evaluate("document.getElementById('simulator').scrollIntoView()")
    page.evaluate("VQCLab.setup({policy: 'vqc', traj: 'multisine', amp: 0.3, freq: 0.5, J: 0.02, tau_c: 0.3, delay: 2})")
    page.evaluate("VQCLab.pause(true)")
    print("simulator state:", page.evaluate("VQCLab.advance(6)"))
    page.wait_for_timeout(1500)
    page.locator("#simulator .sim").screenshot(path=os.path.join(SHOT_DIR, "site-simulator.png"))
    page.locator("#vqc").screenshot(path=os.path.join(SHOT_DIR, "site-vqc.png"))
    page.evaluate("VQCLab.pause(false)")
    page.evaluate("VQCLab.runComparison()")
    page.wait_for_function("window.__compare !== undefined", timeout=180000)
    page.wait_for_timeout(500)
    page.locator("#simulator .compare").screenshot(path=os.path.join(SHOT_DIR, "site-compare.png"))
    cmp = page.evaluate("window.__compare")
    print("browser comparison (mean RMS mrad):", dict(zip(cmp["order"], [round(x, 3) for x in cmp["data"]])))
    page.locator("#fpga").screenshot(path=os.path.join(SHOT_DIR, "site-fpga.png"))
    page.locator("#results").screenshot(path=os.path.join(SHOT_DIR, "site-results.png"))
    page.locator("#hardware").screenshot(path=os.path.join(SHOT_DIR, "site-hardware.png"))
    page.locator("#status").screenshot(path=os.path.join(SHOT_DIR, "site-status.png"))
    page.evaluate("window.scrollTo(0, 0)")
    page.wait_for_timeout(800)
    page.screenshot(path=os.path.join(SHOT_DIR, "site-full.png"), full_page=True)
    print("screenshots in", SHOT_DIR)


if __name__ == "__main__":
    sys.exit(main())
