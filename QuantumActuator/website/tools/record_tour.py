"""Record a guided tour of the website as a video (MP4).

    python -m http.server 8765 --bind 127.0.0.1      (in D:\\robot\\website, if not running)
    python website/tools/record_tour.py [--url http://127.0.0.1:8765/] [--out website/video/vqc_actuator_lab_tour.mp4]

Playwright records the browser (WebM, needs `python -m playwright install ffmpeg`), then
imageio-ffmpeg's ffmpeg converts it to H.264 MP4. Captions are overlaid on the page itself.
"""
import argparse
import os
import shutil
import subprocess
import tempfile
import time

import imageio_ffmpeg
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1600, 900
ARGS = ["--use-gl=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]

HELPERS = """
window.__tour = {
  caption(text) {
    let el = document.getElementById('__cap');
    if (!el) {
      el = document.createElement('div'); el.id = '__cap';
      el.style.cssText = 'position:fixed;left:50%;bottom:28px;transform:translateX(-50%);z-index:9999;' +
        'background:rgba(8,12,24,.86);color:#e7ecf6;border:1px solid #2c3a5c;border-radius:12px;' +
        'padding:12px 22px;font:600 20px Inter,Segoe UI,system-ui,sans-serif;max-width:80%;text-align:center;' +
        'box-shadow:0 8px 30px rgba(0,0,0,.45);transition:opacity .35s';
      document.body.appendChild(el);
    }
    el.style.opacity = 0;
    setTimeout(() => { el.textContent = text; el.style.opacity = text ? 1 : 0; }, 180);
  },
  scrollTo(target, ms) {
    const el = typeof target === 'string' ? document.querySelector(target) : null;
    const y1 = el ? el.getBoundingClientRect().top + window.scrollY - 56 : target;
    const y0 = window.scrollY, t0 = performance.now();
    const ease = (t) => t < .5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
    return new Promise((res) => {
      const step = (now) => {
        const t = Math.min(1, (now - t0) / ms);
        window.scrollTo(0, y0 + (y1 - y0) * ease(t));
        t < 1 ? requestAnimationFrame(step) : res();
      };
      requestAnimationFrame(step);
    });
  },
  slide(id, from, to, ms) {
    const el = document.getElementById(id), t0 = performance.now();
    return new Promise((res) => {
      const step = (now) => {
        const t = Math.min(1, (now - t0) / ms);
        el.value = from + (to - from) * t; el.dispatchEvent(new Event('input'));
        t < 1 ? requestAnimationFrame(step) : res();
      };
      requestAnimationFrame(step);
    });
  },
};
"""


def tour(page):
    J = page.evaluate
    wait = page.wait_for_timeout

    def cap(text):
        J("t => window.__tour.caption(t)", text)

    def scroll(sel, ms=1600):
        J(f"() => window.__tour.scrollTo({sel!r}, {ms})")
        wait(ms + 200)

    # 1. hero
    cap("VQC Actuator Lab — final results (v2.4): a quantum-circuit policy driving a 15:1 cycloidal joint")
    wait(6500)
    # 2. actuator
    scroll("#actuator")
    cap("The actuator, assembled from the project's real STL parts — 15 motor turns per output turn")
    wait(3500)
    J("""() => { const s = document.getElementById('spin'); s.checked = false; s.dispatchEvent(new Event('change')); }""")
    cap("Explode the assembly: housing, 16 ring pins, 15-lobe cycloidal disc, eccentric shaft, output flange")
    J("() => window.__tour.slide('explode', 0, 1, 2500)")
    wait(4200)
    J("() => window.__tour.slide('explode', 1, 0, 1800)")
    wait(2000)
    J("""() => { const c = document.getElementById('cutaway'); c.checked = true; c.dispatchEvent(new Event('change'));
                 const s = document.getElementById('spin'); s.checked = true; s.dispatchEvent(new Event('change')); }""")
    cap("Cut-away: the disc wobbles on a 1.25 mm eccentric while it rolls around the ring pins")
    wait(5000)
    J("""() => { const c = document.getElementById('cutaway'); c.checked = false; c.dispatchEvent(new Event('change')); }""")
    # 3. system
    scroll("#system")
    cap("Residual control: the firmware PD loop stabilises, the VQC adds feed-forward torque")
    wait(5500)
    # 4. simulator
    scroll("#simulator")
    J("VQCLab.setup({policy: 'vqc', traj: 'sine', amp: 0.3, freq: 0.5})")
    cap("The same joint model, firmware loop and trained policies run at 1 kHz in the browser")
    wait(6000)
    page.select_option("#traj", "chirp")
    cap("Chirp trajectory — faster than anything in training")
    wait(5000)
    page.click("#randPlant")
    cap("Randomise the plant: inertia, friction and delay the policy was never told about")
    wait(5000)
    page.select_option("#policy", "mlp")
    cap("Same task with the 65-parameter MLP")
    wait(5000)
    page.select_option("#policy", "pd")
    cap("Firmware PD alone — the error is several times larger")
    wait(4500)
    page.select_option("#policy", "vqc")
    page.select_option("#traj", "sine")
    page.click("#nomPlant")
    # 5. head-to-head
    J("""() => { const el = document.querySelector('#simulator .compare'); el.scrollIntoView({block: 'center'}); }""")
    cap("Head-to-head on 24 random plants: PD vs model FF vs VQC vs MLP")
    wait(800)
    page.click("#compareBtn")
    page.wait_for_function("window.__compare !== undefined", timeout=240000)
    cap("Result: VQC beats PD by far, but the small MLP is still more accurate")
    wait(5000)
    # 6. inside the VQC
    scroll("#vqc")
    cap("Inside the circuit: live encoding angles and |ψ|² over the 64 basis states")
    wait(7000)
    # 7. FPGA
    scroll("#fpga")
    cap("FPGA: the HLS core went from 15,343 to 2,248 cycles — 22.5 µs at 100 MHz")
    wait(6000)
    # 8. results
    scroll("#results")
    cap("Verdict: the VQC works, but shows no parameter advantage — the hypothesis is rejected")
    wait(7000)
    # 9. real hardware
    scroll("#hardware")
    cap("Real hardware, 2026-10-13: the PYNQ drives the actuator open-loop over CAN — 4,000 commands, 0 missed")
    wait(6000)
    J("() => window.__tour.scrollTo(window.scrollY + 520, 1600)")
    wait(1800)
    cap("The USB CAN adapter's 1.8 ms round trip is too slow for 1 kHz; no encoder yet, so no closed loop")
    wait(6500)
    # 10. status
    scroll("#status")
    cap("Honest status: what was measured on hardware, in simulation, and what is still missing")
    wait(6000)
    J("() => window.__tour.scrollTo(0, 2200)")
    cap("VQC Actuator Lab · PYNQ-Z2 · B-G431B-ESC1 · MAD 5010 + 15:1 cycloidal")
    wait(4500)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8765/")
    ap.add_argument("--out", default=os.path.join(ROOT, "video", "vqc_actuator_lab_tour.mp4"))
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="tour_")
    with sync_playwright() as pw:
        b = pw.chromium.launch(channel="chrome", headless=True, args=ARGS)
        ctx = b.new_context(viewport={"width": W, "height": H}, device_scale_factor=1,
                            record_video_dir=tmp, record_video_size={"width": W, "height": H})
        page = ctx.new_page()
        t_video = time.monotonic()          # the recording starts with the page
        page.goto(a.url, wait_until="networkidle")
        page.wait_for_function("document.body.dataset.ready === '1' && window.VQCLab && window.VQCLab.ready()", timeout=90000)
        page.add_script_tag(content=HELPERS)
        page.wait_for_timeout(2500)         # let the hero 3D settle
        offset = max(0.0, time.monotonic() - t_video - 0.5)   # cut the page-loading part
        tour(page)
        webm = page.video.path()
        ctx.close()
        b.close()
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run([ff, "-y", "-loglevel", "error", "-i", webm, "-ss", f"{offset:.2f}", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-r", "25", "-movflags", "+faststart", a.out], check=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print("wrote", a.out, f"{os.path.getsize(a.out) / 1e6:.1f} MB", f"(trimmed {offset:.1f} s of page loading)")


if __name__ == "__main__":
    main()
