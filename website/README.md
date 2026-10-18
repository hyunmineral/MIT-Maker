

```
cd website
python3 -m http.server 8765 --bind 127.0.0.1
# open http://127.0.0.1:8765/
```
(ES modules and `fetch` need an HTTP server; opening `index.html` from disk will not work.)

## Sections
| id | content |
|---|---|
| `#hero` | auto-rotating actuator driven by a background PD + VQC run |
| `#actuator` | explode slider, cut-away housing, part labels, output-angle slider, live kinematics readout |
| `#system` | residual architecture and control-rate layers |
| `#simulator` | policy / trajectory / plant controls, 3D joint with target ghost, live charts, RMS/max metrics, 24-plant head-to-head |
| `#vqc` | circuit diagram with live encoding angles, live \|ψ\|² over 64 basis states, ⟨Z₀⟩ and τ_ff gauges |
| `#fpga` | HLS iterations, board latency (PL vs PS), utilisation |
| `#results` | policy comparison (VQC vs MLP), verdict, goals G1–G5 |
| `#hardware` | 2026-10-13 open-loop run from the raw log (commanded vs applied angle, phase current), CAN round trip vs 1 ms, the CAN faults and the FIFO bug |
| `#status` | measured on hardware / in simulation / not done |

## Files
| path | what |
|---|---|
| `index.html`, `css/style.css` | page and theme |
| `js/policy.js` | VQC (fused gates, CNOT-ring permutation), MLP 6-8-1, model FF, PD — same math as `pynq-can/vqc` |
| `js/sim.js` | joint + Recoil firmware loop + 1 kHz host loop (mirrors `actuator_sim.py` / `run_controller.py`) |
| `js/actuator3d.js` | three.js view: STL assembly, cycloidal kinematics (θ_motor = −15 q, disc on 1.25 mm eccentric), explode, cut-away, labels |
| `js/viz.js` | strip charts, circuit SVG, probability bars |
| `js/main.js` | wiring, Chart.js result charts, `window.VQCLab` self-test hooks |
| `models/*.stl` | the actuator's printable parts (from `5010+Cycloidal+Gear+Actuator`) |
| `data/policies.json` | trained VQC (72 angles) and MLP (65 weights) parameters, encoding, plant model |
| `data/results.json` | measured results (copy of `docs/results/results.json`) |
| `data/hw_openloop.json` | first real-hardware log at 100 Hz (`tools/export_hw_log.py` from `docs/results/logs/openloop_pynq_2026-10-13.csv`) |
| `data/reference.json` | Python reference outputs for the browser self-test |
| `vendor/` | three.js 0.160 (+ OrbitControls, STLLoader, CSS2DRenderer, RoomEnvironment), Chart.js 4.4.1 |
| `tools/export_data.py` | regenerate `data/` from the trained models |
| `tools/verify_site.py` | headless-Chrome check (errors, JS ≡ Python) and screenshots → `img/` |

## Verification (2026-10-06)
`python tools/verify_site.py --shots` (Playwright + local Chrome, SwiftShader WebGL):
- policy outputs, JS vs Python: VQC 1.4e-7, MLP 6.5e-8, model FF 0
- closed loop (sine 0.3 rad / 0.5 Hz, 4 s, RMS after 1 s), JS = Python to 4 decimals:
  PD 6.0093, model FF 0.1662, VQC 1.2159, MLP 0.8107 mrad
- no console or page errors; no horizontal overflow at 390 px width
- 24-plant browser comparison (sine, seed 7): PD 6.85, model FF 0.78, VQC 1.30, MLP 1.04 mrad

## Tour video
`video/vqc_actuator_lab_tour.mp4` (2:51, 1600×900, H.264, 25 fps) is a captioned walk through every section,
recorded from the live site (hero, actuator explode/cut-away, architecture, simulator with policy/trajectory/plant
changes, 24-plant head-to-head, inside the VQC, FPGA, results, real hardware, status):
```
python -m playwright install ffmpeg      # once: Playwright's screen recorder
pip install imageio-ffmpeg               # once: ffmpeg for the WebM -> MP4 conversion
python website/tools/record_tour.py      # needs the local server on :8765
```
