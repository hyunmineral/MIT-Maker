# docs — Documentation Guide (v2.4, 2026-10-13)

v2.0 is the edition that reflects results actually implemented and measured on 2026-10-04–06. All assumed figures from v1.0 (2026-10-03) have been replaced with measured values.
**2026-10-13: The ESC was replaced with a new one and the real actuator was moved for the first time** (PYNQ → CANable → ESC, open-loop). There is no encoder, so the closed-loop and VQC hardware comparison has not been done yet (report §4.9). Control performance was measured in simulation and with the ESC emulator on the PYNQ-Z2.

| Document | Content | Format |
|---|---|---|
| `actuator-vqc-control-report` | Development report (all results, problem solving, goal assessment) | .md / .docx / .pptx |
| `actuator-vqc-control-report-scenario` | **Hardware test scenario (prediction edition)**: test procedure T0–T9 assuming ESC recovery, predicted values and their basis, judgment criteria. Measured columns left blank | .md / .docx |
| `paper-vqc-actuator` | The same results in paper format (writing style for general readers) | .md / .docx |
| `guide-for-beginners` | Explanation for complete beginners | .md / .docx / .pptx |
| `besc1-firmware-bringup/README.md` | ESC firmware bring-up record (+ 2026-10-13 status) | .md |
| `besc1-firmware-bringup/MOVE_WITHOUT_CAN.md` | **How to move the actuator without CAN or the PYNQ**: hand check, manual PSU stepping, button demo firmware (`Recoil-Motor-Controller-BESC/demo/`) | .md / .docx |
| `besc1-firmware-bringup/BOARD_REPLACEMENT.md` | **New ESC board replacement procedure** in 12 steps (pre-soldering check → firmware → CAN wiring and termination measurement → soldering rules → work log) | .md / .docx |
| `besc1-firmware-bringup/CAN_SETUP.md` | CAN path: working CANable (slcan) path and diagnosis record; PS CAN path unresolved | .md |
| `results/results.json`, `results/logs/*.csv` | Raw data for the report's figures | JSON / CSV |
| `figures/png`, `figures/svg` | Figures (fig1·3·5·7·14·15 generated from measured data, fig16–24 are website captures) | PNG / SVG |
| `website` | English website **VQC Actuator Lab** (three.js 3D actuator + in-browser simulator). Report §4.8, guide Appendix D | HTML / JS |

## Rebuilding

```
python docs/tools/collect_results.py      # training results + measurements → results.json, fill md placeholders
python docs/tools/make_figures.py         # generate measured-data figures
python docs/tools/update_concept_figures.py   # fix numbers in concept-diagram SVGs + render PNGs (Chrome headless)
python docs/tools/build_docx.py           # md → docx
python docs/tools/build_pptx.py           # presentation slides
python website/tools/verify_site.py --shots  # website verification + captures
python docs/tools/sync_site_figures.py           # copy captures website/img → figures/png/fig16–24
```

The implementation code and how to run it are in `pynq-can/README.md`.
