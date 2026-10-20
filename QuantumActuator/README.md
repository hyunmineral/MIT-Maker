# VQC Actuator

Quantum-circuit (VQC) feed-forward control of a robot joint, with the circuit simulated on a PYNQ-Z2 FPGA.

A 6-qubit variational quantum circuit (72 trained angles, simulated classically) adds feed-forward torque on top
of the motor controller's own PD position loop (**residual architecture**). The circuit's 64-amplitude state-vector
simulation runs in the PYNQ-Z2 programmable logic (PL), the 1 kHz control loop runs on its ARM cores (PS), and
commands reach the motor controller over CAN. The plant is one Berkeley Humanoid Lite joint: a MAD 5010 110KV motor
with a 15:1 cycloidal reducer, driven by a B-G431B-ESC1 running the Recoil firmware.

```
 PYNQ-Z2 PS (Linux, 1 kHz)                 CAN 1 Mbps                B-G431B-ESC1 (Recoil)
 trajectory → features → VQC → τ_ff  ── RPDO3 [q_ref, τ_ff] ──▶  τ = kp(q_ref−q) − kd·q̇ + τ_ff  (2 kHz)
 PL: 64-amplitude state vector → ⟨Z₀⟩ ◀── TPDO3 [q, τ] ──────────  FOC 10 kHz → MAD 5010 + 15:1 cycloidal
```

## Status

| Area | State |
|---|---|
| Policy (simulation, 256 randomized joints) | VQC 1.43 ± 0.07 mrad vs PD-only 8.79 mrad. A same-size MLP (65 params) reaches 0.98 ± 0.01 mrad → **no parameter advantage for the VQC** |
| FPGA | HLS core 2,248 cycles = 22.5 µs @ 100 MHz (timing met); PL inference path 29.0 µs vs 64.6 µs on the ARM core; PL = PS within 4·10⁻⁷ |
| Real-time loop | 1 kHz on the PYNQ-Z2, jitter p99 4.1 µs (motor controller emulated in-process) |
| Real hardware | Open-loop drive works (PYNQ → CANable → ESC, 4,000 commands, 0 missed, RTT p50 1.81 ms). **No encoder fitted yet → no closed loop** |
| CAN | USB CANable path works but is too slow for 1 kHz; the on-chip PS CAN0 + SN65HVD230 path does not work yet |

Detailed results: [`docs/actuator-vqc-control-report.md`](docs/actuator-vqc-control-report.md). Next work: [`ROADMAP.md`](ROADMAP.md).

## Repository layout

| Path | What |
|---|---|
| [`pynq-can/`](pynq-can/) | Everything that runs on (or builds for) the PYNQ-Z2: [`host/`](pynq-can/host/) (1 kHz controller, Recoil CAN protocol over SocketCAN/slcan, emulator, tests), [`vqc/`](pynq-can/vqc/) (circuit model, training, C kernel, PL driver, trained runs — **the 6-qubit circuit is defined in [`vqc/vqc_model.py`](pynq-can/vqc/vqc_model.py)**), [`hls/`](pynq-can/hls/) (Vitis HLS core + testbench), [`vivado/`](pynq-can/vivado/) (bitstream Tcl, board files, prebuilt `out/`), CAN0 device-tree overlay + boot service |
| [`Recoil-Motor-Controller-BESC/`](Recoil-Motor-Controller-BESC/) | Recoil firmware for the B-G431B-ESC1 (upstream MIT) with local options (open loop without encoder, demo, CAN termination, RX FIFO fix); [`demo/`](Recoil-Motor-Controller-BESC/demo/) holds the make-free build script, prebuilt ELFs and SWD tools |
| [`website/`](website/) | "VQC Actuator Lab": three.js actuator model from the real STLs, in-browser 1 kHz simulator, results and real-hardware pages |
| [`docs/`](docs/) | Report, paper, beginner's guide, test scenario, hardware procedures (Markdown), figures, raw data ([`results/`](docs/results/)), and the tools that build figures/docx/pptx |
| [`hardware/`](hardware/) | Actuator CAD (printable STL parts) and PYNQ SD-card scripts |

## Quick start

```bash
# website (no install needed)
cd website && python -m http.server 8765            # open http://127.0.0.1:8765/

# simulation and training (PC, Python 3.12 + numpy + torch)
cd pynq-can/vqc && python train.py --out vqc_params.json
cd pynq-can/host && python -m unittest test_recoil

# firmware (arm-none-eabi-gcc from STM32CubeIDE; set ARM_GCC_BIN if it is elsewhere)
bash Recoil-Motor-Controller-BESC/demo/build_variant.sh recoil_openloop -DOPENLOOP_NO_ENCODER=1
```

Board setup, flashing, real-hardware runs and all build steps: [`DEVELOPMENT.md`](DEVELOPMENT.md).

## Documentation

| Document | Contents |
|---|---|
| [`docs/actuator-vqc-control-report.md`](docs/actuator-vqc-control-report.md) | Full technical record: architecture, results, 24 troubleshooting entries, goals, reproduction |
| [`docs/paper-vqc-actuator.md`](docs/paper-vqc-actuator.md) | The results as a short paper |
| [`docs/actuator-vqc-control-report-scenario.md`](docs/actuator-vqc-control-report-scenario.md) | Planned closed-loop hardware tests T0–T9 with **predicted** values |
| [`docs/guide-for-beginners.md`](docs/guide-for-beginners.md) | Background for readers new to FOC, VQCs or FPGAs |
| [`docs/besc1-firmware-bringup/`](docs/besc1-firmware-bringup/) | ESC bring-up log, CAN setup and diagnosis, board replacement procedure, encoder-free operation |

Documentation rule used throughout: only measured numbers are reported as results; predictions and estimates are
labelled as such, and negative results are kept.

## License

Third-party components keep their own licenses (see [`THIRD_PARTY.md`](THIRD_PARTY.md)). A license for the
project's own code has not been chosen yet (see `ROADMAP.md`).
