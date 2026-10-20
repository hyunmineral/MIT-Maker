"""Copy the website screenshots (made by website/tools/verify_site.py --shots) into docs/figures/png.

    python docs/tools/sync_site_figures.py
"""
import os
import shutil

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(os.path.dirname(D), "website", "img")
SHOTS = {"site-hero.png": "fig16-site-hero.png", "site-actuator-exploded.png": "fig17-site-actuator-exploded.png",
         "site-actuator-cutaway.png": "fig18-site-actuator-cutaway.png", "site-simulator.png": "fig19-site-simulator.png",
         "site-vqc.png": "fig20-site-vqc.png", "site-compare.png": "fig21-site-compare.png",
         "site-fpga.png": "fig22-site-fpga.png", "site-results.png": "fig23-site-results.png",
         "site-hardware.png": "fig24-site-hardware.png"}
for src, dst in SHOTS.items():
    shutil.copy2(os.path.join(IMG, src), os.path.join(D, "figures", "png", dst))
print("copied", len(SHOTS), "screenshots")
