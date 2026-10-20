# Development Report: Robot Actuator Control System with a Variational Quantum Circuit Policy

**Project**: Berkeley Humanoid Lite actuator control + FPGA acceleration of a VQC policy
**Date**: 2026-10-06 (v2.4 update: 2026-10-13)
**Version**: 2.4 (edition reflecting actual development results + web visualization + ESC replacement + **real-hardware open-loop drive**)
**Implementation repository**: `pynq-can` (board: `~/vqc_ctrl/`)

> 📋 **Nature of this document — how it differs from v1.0**
> v1.0 (2026-10-03) was a **scenario document that assumed** the development goals had been achieved. Editions from v2.0 on (currently v2.4) report **only results actually implemented and measured** during 2026-10-04~13. All of v1.0's assumed figures (jitter ±9 µs, inference 9.4 µs, +23.4 % vs. MLP, etc.) have been discarded; the correspondence is summarized in Appendix §9.5.

> ⚠️ **Measurement scope — read this first**
> **All control-performance figures are from simulation and HIL.** The original B-G431B-ESC1 failed because a component overheated during soldering (§5.7); on 2026-10-13 it was replaced with a new board and **the real actuator was moved for the first time** (§4.9). However, **with no encoder (AS5600), only open-loop drive** was performed, and CAN went through a USB adapter (CANable), which was too slow for a 1 kHz loop. Therefore **real-hardware closed-loop control and a real-hardware VQC comparison have not yet been done.** The control-performance figures were obtained through the following two paths.
> 1. **Simulation**: the Recoil firmware position loop and a joint dynamics model (`vqc/actuator_sim.py`)
> 2. **PYNQ-Z2 real-hardware HIL**: uses the real Zynq PS CAN controller (loopback mode) and the real PL bitstream, with only the ESC replaced by a firmware emulator (`host/virtual_recoil.py`)
>
> The FPGA bitstream, CAN pin path, PL inference core, and 1 kHz control loop were **measured on real hardware**. The real-hardware open-loop drive and the real-bus RTT are also measured (§4.9).

> 🧪 **Real-hardware test plan**: The closed-loop real-hardware test procedure, predicted values, and pass criteria for after the encoder is mounted and the 1 kHz CAN path is restored are in the separate document `actuator-vqc-control-report-scenario.md` (prediction edition). All figures in that document are predictions, not results of this report.

> 🖼 **Figure numbering**: Figure numbers come from the shared figure set (`figures/`) used by both the report and the guide, so they are not consecutive in this document (e.g., Figures 4, 6, and 9~13 appear only in the guide).

> ⚛️ **Terminology note**: "Quantum" in this work means a **parameterized quantum circuit (VQC) simulated on a classical FPGA/CPU**. No real quantum hardware is used.

---

## Summary

| Item | Result |
|---|---|
| Control architecture | **Residual architecture**: firmware PD (2 kHz) stabilizes, VQC supplies feed-forward torque (1 kHz) |
| Policy performance (simulation, domain randomization) | VQC (72 parameters) RMS **1.43 ± 0.07 mrad**, about 6× better than PD alone at 8.79 mrad |
| **VQC vs MLP** | A similarly sized MLP (65 parameters) is about 32% more accurate than VQC at **0.98 ± 0.01 mrad** → **no parameter-efficiency advantage for VQC was observed** |
| FPGA inference core | HLS state-vector core **22.5 µs @ 100 MHz**, timing met (WNS +0.366 ns), LUT 29 %, DSP 33 % |
| PL inference path (C driver, measured on board) | **p50 29.0 µs / p99 29.8 µs**. 2.2× faster than the PS C kernel (64.6 µs), with output matching PS to float-rounding level (≤ 4e-7) |
| 1 kHz loop jitter (PYNQ, SCHED_FIFO) | `--sim` with the ESC emulator in the same process + VQC-PL: **p50 1.2 / p99 4.1 / max 4.7 µs** |
| CAN | PS CAN0 → EMIO → Pmod JA bitstream complete, pin path confirmed working. Loopback ping-pong RTT p50 482 µs, loss 1.1 % |
| Web visualization | English site **VQC Actuator Lab** (three.js): 3D actuator built from the real STLs, in-browser 1 kHz simulator. Reproduces the same RMS as Python (§4.8) |
| Real motor drive | ⚠️ **Only open-loop drive succeeded** (2026-10-13, new ESC): PYNQ → CANable → ESC, 4,000 commands with 0 dropped, output-shaft motion visually confirmed. Real-bus RTT p50 1.81 ms (via USB). **No encoder, so closed-loop and real-hardware VQC comparison not performed** (§4.9) |

---

## 1. Development Purpose

### 1.1 Background

Berkeley Humanoid Lite is a low-cost humanoid platform in which each joint is a quasi-direct-drive actuator with a **BLDC motor + cycloidal reducer + FOC controller** structure. Control policies are trained in simulation and transferred to real hardware (sim-to-real).

The standard approach runs MLP policy inference on a general-purpose CPU, but scaling to many joints makes parameter count, inference jitter, and power into constraints. This project examines a VQC policy and FPGA inference as an alternative.

### 1.2 Research Question

> **If a parameterized quantum circuit (VQC) is used as the policy representation, can it achieve equivalent actuator control performance with fewer parameters than an MLP? And can its inference be performed on an FPGA deterministically with low latency?**

The answer as of v2.0 (§8): for this task, the first question is **no** (an MLP of the same size is more accurate), and the second is **yes** (PL core 22.5 µs, inference path 29 µs, 2.2× faster than PS with 0.8 µs timing spread, timing met).

### 1.3 Development Goals and Success Criteria

| # | Goal | Success criterion | Result (§6) |
|---|---|---|---|
| G1 | Establish single-axis actuator FOC control | Mode switching and command tracking over CAN | ⚠️ Partial (CAN mode switching + open-loop drive, no encoder) |
| G2 | PYNQ-Z2 real-time control host | 1 kHz via PS CAN, jitter < 20 µs | ⚠️ Conditionally met (`--sim` p99 4.1 µs) |
| G3 | VQC policy PL implementation | 6 qubits, 4 layers, inference < 10 µs | ⚠️ Implemented and verified, core 22.5 µs (misses 10 µs) |
| G4 | Performance verification vs MLP | Error difference < 25 %, 50× parameter reduction | ❌ Hypothesis rejected |
| G5 | sim-to-real transfer | Apply simulation-trained policy to real hardware without retraining | ⏳ Not performed (no encoder) |

---

## 2. System Architecture

### 2.1 Overall Configuration

![Figure 1. System architecture (v2.4)](figures/png/fig1-system-architecture.png)

**Figure 1. System architecture (v2.4, residual architecture)**

```
 PYNQ-Z2 PS (Linux, SCHED_FIFO, pinned to CPU1)                B-G431B-ESC1 (Recoil 0x20250226)
 ┌────────────────────────────────────────────────┐  RPDO3    ┌──────────────────────────────────┐
 │ trajectory → ObsBuilder(8) → feat cos/sin(12)  │─[q_ref,──▶│ MODE_POSITION, 2 kHz             │
 │        ↓ AXI-Lite                              │  τ_ff]    │ τ = kp(q_ref−q) − kd·q̇ + τ_ff    │
 │  PL vqc_top: 64-amplitude state vector → ⟨Z₀⟩  │           │ EMA(α=0.27), clamp ±1 → FOC 10kHz│
 │        ↓                                       │◀─[q, τ]───│                                  │
 │ τ_ff = 0.8·tanh(2⟨Z₀⟩), safety monitor         │  TPDO3    └──────────────────────────────────┘
 │ PS CAN0 → EMIO → Pmod JA (JA1 TX, JA2 RX)      │── SN65HVD230 (not working, §5.22) / CANable USB (real hardware, 2026-10-13) ── CAN 1 Mbps
 └────────────────────────────────────────────────┘
```

### 2.2 Control Hierarchy

| Layer | Location | Rate | Role |
|---|---|---|---|
| Current (FOC) | STM32G431 | 10 kHz | d-q current loop, SVPWM |
| Position PD | STM32G431 | 2 kHz | `τ = kp·e − kd·q̇ + τ_ff` (kp=20, kd=0.15) |
| **Policy (VQC feed-forward)** | PYNQ-Z2 PS+PL | 1 kHz | Torque τ_ff compensating inertia, friction, and damping |
| Trajectory/supervision | PYNQ-Z2 PS | 1 kHz | Target generation, error-limit and missed-response monitoring |

**Difference from v1.0 — adoption of the residual architecture.** In v1.0, the VQC produced the entire torque. When the VQC was actually trained to imitate a PID controller, the smooth circuit function could not reproduce the high-gain linear region near zero and explained only about 74 % of the label variance (MSE 0.014, variance 0.053). The roles were therefore split as follows.
- **Firmware PD**: handles stabilization. Runs inside the ESC at 2 kHz.
- **VQC**: handles feed-forward.

In this architecture, a wrong policy output does not destabilize the joint; it only increases the tracking error. This is also advantageous for real-hardware safety. Recoil's RPDO3 `[q_ref, τ_ff]` message fits this architecture as-is.

### 2.3 VQC Policy Circuit

![Figure 2. VQC policy circuit structure (6 qubits · 4 layers · 72 parameters)](figures/png/fig2-vqc-circuit.png)

**Figure 2. VQC policy circuit structure (6 qubits · 4 layers · 72 parameters)**

| Item | Value |
|---|---|
| Qubits / layers / trainable parameters | 6 / 4 / **72** (6 × 3 axes × 4 layers) |
| Layer composition | `RY(x_q) → RX(θ) → RY(θ) → RZ(θ)` (per qubit), followed by CNOT ring 0→1→…→5→0 |
| Encoding | `x_q = π·tanh(s_q·f_q)`, re-uploaded every layer |
| Input features f (6) | ∫e, q̇_ref, q̈_ref, q̇, q_ref, e (scales 10, 0.25, 0.02, 0.25, 1.0, 2.0) |
| Output | `τ_ff = 0.8·tanh(2·⟨Z₀⟩)` [firmware torque units, N·m] |
| Numerical precision | float32 complex, 64 amplitudes |

**Lesson from input design**: The first design included the previous output τ_prev and a high-gain error in the input. The policy output then fed back into itself and the torque oscillated (dtau_rms 0.029 → 0.0026 with τ_prev removed). Since feedback is handled by the firmware PD, the input was changed to be **reference-trajectory-centered**, with the error included only at low gain.

### 2.4 PS/PL Partitioning (Final)

| Stage | Location | Notes |
|---|---|---|
| Observation generation | PS (Python) | 8 values |
| Features and 12 `cos/sin(x/2)` → register writes → start and poll → `tanh` | PS (C driver `vqc_pl_driver.c`, one ctypes call) | Direct `/dev/mem` access |
| Fusion of parameter-only rotations `RZ·RY·RX` → 24 2×2 matrices | PS (once at initialization) | Loaded into PL over AXI-Lite |
| State-vector simulation (24 gates + 4 CNOT rings) → ⟨Z₀⟩ | **PL** (`vqc_top`) | 2,248 cycles (22.5 µs) |

Initially everything, including tanh, cos, and sin, was placed in PL. This produced a phenomenon where **C/RTL co-simulation passed but the board alone gave wrong answers for mid-range inputs** (§5.17). The transcendental functions were therefore moved to PS. The state vector, which accounts for most of the computation, is still handled by PL.

### 2.5 Software and Hardware Components

| Path | Contents |
|---|---|
| `make_can0_dtbo.py`, `can0-overlay.service`, `load_overlay.py` | Enable PS CAN0 at boot (device tree overlay), CAN reference clock 100 MHz, load PL overlay, 1 Mbps · SP 0.8 |
| `vivado/build_can0_overlay.tcl` | Bitstream: CAN0 → EMIO → Pmod JA (+ VQC core) |
| `hls/vqc_top.c`, `run_hls.tcl`, `cosim.tcl` | HLS core, C simulation, synthesis, IP export, C/RTL co-simulation |
| `vqc/vqc_kernel.c` | float32 kernel shared by PS (`libvqc.so`) and HLS |
| `vqc/vqc_model.py`, `train.py`, `actuator_sim.py` | Circuit definition, training (BC + BPTT), joint and firmware model |
| `host/recoil.py`, `recoil_cli.py` | Recoil CAN protocol (SocketCAN, standard library only), diagnostic CLI |
| `host/run_controller.py` | 1 kHz controller (`--sim`, `--policy pd/model_ff/vqc`, `--pl`) |
| `host/vqc_pl.py` | PL core driver |
| `host/recoil_emulator.py`, `virtual_recoil.py` | Firmware CAN-handling emulator + joint model |

---

## 3. Development Process (Actual)

![Figure 7. Actual development timeline](figures/png/fig7-timeline.png)

**Figure 7. Actual development timeline**

| Date | Phase | Result |
|---|---|---|
| 2026-09-20 | P1 Firmware bring-up | ✅ Recoil build and flash, option bytes, motor profile (§5.1~5.6) |
| 2026-10-03 | P2 Board reconnection | ❌ No SWD/JTAG response. Cause: a component overheated during soldering (user report 2026-10-07, §5.7) |
| 2026-10-04 | P3 PYNQ image | ✅ PYNQ-Z2 v3.1.1 SD written and fully verified |
| 2026-10-05 | P4 PYNQ bring-up | ✅ Direct network link, SSH, PS CAN0 overlay, loopback |
| 2026-10-05 | P5 Host software | ✅ Recoil driver, 1 kHz controller, emulator, unit tests |
| 2026-10-05 | P6 VQC policy | ✅ Switched to residual architecture, training (BC + BPTT, domain randomization) |
| 2026-10-06 | P7 FPGA | ✅ Vivado 2024.1, HLS optimization (15,343 → 2,248 cycles), 2 bitstreams |
| 2026-10-06 | P8 Comparison experiments | ✅ 6 MLP baselines, 3 VQC seeds, PL measured |
| 2026-10-13 | P9 New ESC + real-hardware open-loop | ⚠️ New board bring-up passed, no encoder → open-loop build, PYNQ → ESC drive via CANable succeeded (§4.9, §5.20~5.24) |

### 3.1 P1 — Firmware bring-up (2026-09-20, actual record)

The Recoil firmware was built and flashed to the B-G431B-ESC1. Details are in `besc1-firmware-bringup/README.md`.

| Task | Result |
|---|---|
| ST-LINK firmware | V2J28M18 → V2J48M35 |
| Firmware build | 48.7 KB ELF (Flash 38 %) |
| Option bytes | `nSWBOOT0=0 nBOOT0=1` |
| Motor profile | `MOTORPROFILE_MAD_5010_110KV` |
| CAN adapter / motor rotation | ⏳ Not performed because the adapter had not arrived (→ open-loop performed with the new ESC on 2026-10-13, §4.9) |

### 3.2 P2 — ESC reconnection failure (2026-10-03)

About two weeks later, SWD/JTAG stopped responding with `Unable to get core ID`. At the time the cause could not be identified. A user report on 2026-10-07 confirmed it was **a failure caused by a component overheating during soldering** (§5.7). v1.0 stated "recovered by board replacement," but that was an assumption; **as of v2.0 (10-04~06) there was no record of an actual replacement or recovery** (the actual replacement was on 2026-10-13, §4.9). During that period it was confirmed that the ESC and ST-LINK were not connected to the PC.

### 3.3 P3~P4 — PYNQ-Z2 bring-up (2026-10-04~05)

1. **SD image**: `pynq_z2_v3.1.1.img` (7.76 GB) was written and verified by comparing every byte.
2. **Network**: 192.168.2.1/24 was set on the PC Ethernet and the board (192.168.2.99) was connected directly. SSH uses key authentication (`ssh pynq`). The board runs PynqLinux 3.0, kernel 6.6.10, pynq 3.1.1.
3. **PS CAN0**:
   - The kernel already had `CONFIG_CAN_XILINXCAN=y`, and `can@e0008000` in the device tree was `disabled` with its clocks defined.
   - The board has no `dtc`, so the overlay was built on the PC with Python `fdt` to change it to `status="okay"`. It was applied via configfs and registered as a systemd service.
   - The CAN reference clock was 8 MHz, giving only 8 tq per bit at 1 Mbps. It was raised to 100 MHz (20 tq) with the overlay's `assigned-clock-rates`, and the sample point was set to 0.8 to match Recoil.
4. **Loopback self-test**: 5000/5000 frames, Python round-trip median 236 µs.

### 3.4 P5 — Host software (2026-10-05)

- **`recoil.py`**: The firmware's `MotorController_handleCANMessage()` was read and the protocol implemented exactly. Supported features are NMT, ping, SDO read/write, RPDO2/3, heartbeat, and Flash save. The PYNQ image has no python-can, so only the standard `socket.AF_CAN` is used.
- **Emulator**: Emulates the firmware's CAN handling byte-for-byte, with a joint model attached. Unit tests pass 5/5.
- **`run_controller.py`**: Runs the 1 kHz loop.
  - Timing: waits on absolute time, spins for the last 300 µs, GC disabled during the loop.
  - Safety: stops and transitions DAMPING → IDLE when error exceeds 0.3 rad. If no PDO response arrives within 0.8 ms, holds the previous value; stops after 5 consecutive misses.
- **Bug fixes**: Found and fixed a bug where a stale response was mistaken for the current one (§5.13) and request backlog in the virtual device (§5.14).

### 3.5 P6 — VQC policy training (2026-10-05~06)

1. **Joint and firmware model**:
   - Includes inertia J, viscous b, Coulomb friction τ_c, efficiency η, and delay 0~2 ms.
   - Reflects the firmware's 2 kHz PD, EMA filter, torque limit ±1, and output velocity limit 18 rad/s.
   - Randomization ranges during training: J 0.007~0.028, b 0.02~0.10, τ_c 0.05~0.40, η 0.75~0.92.
2. **Stage 1 BC**: trained to imitate nominal inverse-dynamics feed-forward (600 epochs).
3. **Stage 2 BPTT**: fine-tuned by closed-loop backpropagation.
   - 600 steps, truncated BPTT cut into 100-step segments.
   - Domain randomization applied; steps with abnormal gradients (NaN, inf) are skipped.
4. **Control group**: two MLPs were trained with the same inputs and the same procedure (6-8-1, 6-64-64-1). Three seeds each.

### 3.6 P7 — FPGA implementation (2026-10-06)

1. **Vivado 2026.1 could not run**:
   - Windows 11 Smart App Control blocked unsigned DLLs.
   - From 2026.1, even free use requires a license file, and the Basic license issuance list was empty.
   - So **Vivado 2024.1, which requires no license,** was installed (§5.11~5.12).
2. **HLS optimization**: Reduced from 15,343 cycles to 2,248 cycles over five stages (v1~v5) (153 µs → 22.5 µs at 100 MHz) (§4.5, §5.16).
3. **Two bitstreams**:
   - `can0.bit`: CAN only
   - `vqc_can0.bit`: CAN + VQC core
4. **PL wrong-answer problem**: The board gave wrong answers; the cause was traced and the architecture changed to a PS/PL partitioned structure (§5.17).

---

## 4. Test Results

### 4.1 Test Environment

| Category | Configuration |
|---|---|
| Training/evaluation PC | Windows 11, Python 3.12, PyTorch 2.14 CPU |
| Board | PYNQ-Z2, PynqLinux 3.0, Python 3.10 venv, gcc 11.2 |
| FPGA tools | Vivado / Vitis HLS 2024.1 |
| Simulation evaluation | 256 episodes × 3 s, first 0.5 s excluded. Reference trajectory is a sum of 2 sinusoids (amplitude 0.025~0.25 rad, 0.2~1.5 Hz) |
| PYNQ run evaluation | 0.3 rad · 0.5 Hz sinusoid, 1 s ramp at start, 6~10 s |

### 4.2 Numerical Consistency (do all implementations compute the same function?)

| Comparison | Max error |
|---|---|
| torch batch simulator ↔ numpy gate-by-gate reference | 1.1e-7 |
| Fused-gate numpy ↔ reference | 2.6e-7 |
| CNOT ring permutation ↔ 6 CNOTs applied sequentially | Match |
| PS C kernel (Cortex-A9) ↔ reference (trained parameters) | 3.0e-7 |
| HLS C simulation ↔ reference | 4.2e-7 |
| **HLS C/RTL co-simulation** ↔ reference | 9.5e-7, PASS |
| **PL core (board)** ↔ PS C kernel, trained parameters (64 test vectors / 500 random inputs) | 3.7e-7 / 3.9e-7 |
| PL path ↔ PS C kernel, synthetic-weight C bench (board, 20,000 runs) | 0 |

### 4.3 Policy Comparison — Key Results

![Figure 3. VQC vs MLP vs classical baselines](figures/png/fig3-vqc-vs-mlp.png)

**Figure 3. VQC vs MLP vs classical baselines**

All trained policies used the same input encoding, the same output squashing, and the same training procedure. Values in the table are RMS tracking error; trained policies are mean ± standard deviation (3 seeds).

| Policy | Trainable parameters | Randomized RMS [mrad] | Nominal RMS [mrad] | Randomized max [mrad] |
|---|---|---|---|---|
| Firmware PD only | 0 | 8.79 | 8.53 | 36.4 |
| PD + nominal model feed-forward | 0 | 1.55 | 1.10 | 8.1 |
| **PD + VQC** | **72** | **1.43 ± 0.07** | 1.09 ± 0.12 | 18.7 |
| PD + MLP 6-8-1 | 65 | 0.98 ± 0.01 | 0.53 ± 0.05 | 10.5 |
| PD + MLP 6-64-64-1 | 4,673 | 1.01 ± 0.01 | 0.61 ± 0.01 | 12.3 |

**Interpretation**
1. **The VQC works.** Its error is about 6× smaller than with PD alone, and comparable to nominal model feed-forward.
2. **An MLP of the same size beats the VQC.** The 65-parameter MLP's error is about 32 % smaller than the VQC's (equivalently, the VQC's error is about 47 % larger). In this task, a parameter-efficiency advantage for the VQC was **not observed**.
3. **A large MLP gives no gain either.** The 4,673-parameter MLP is no better than the 65-parameter MLP, so the task itself is simple and a small model suffices. v1.0's assumed "4,801 MLP parameters vs 72 VQC parameters, 66.7× reduction" was unfair from the comparison baseline onward.
4. **The maximum error occurs on the steepest trajectory.** The startup transient is not the cause. In the same episode (#149) with 2 ms delay, model FF was 8.1 and VQC (seed 0) was 19.3 mrad. The median per-episode maximum error is VQC 2.25 and model FF 1.64 mrad.

### 4.4 PYNQ-Z2 Run Results (1 kHz)

![Figure 15. 1 kHz control run on the PYNQ-Z2](figures/png/fig15-tracking-pynq.png)

**Figure 15. 1 kHz control run on the PYNQ-Z2**

The condition is 0.3 rad · 0.5 Hz sinusoid tracking; values in the table are RMS / max error [mrad].

| Policy | `--sim` (in-process emulator) | CAN loopback + virtual ESC |
|---|---|---|
| PD only | 6.01 / 8.32 | 6.31 / 10.18 |
| PD + model FF | 0.17 / 0.29 | 0.38 / 1.34 |
| PD + VQC (PS C kernel) | 1.21 / 2.78 | 1.45 / 3.34 |
| PD + VQC (**PL core**) | 1.21 / 2.78 (same as PS) | 1.38 / 3.47 |

In `--sim`, the PS and PL results match to the second decimal place because the τ_ff difference between the two paths is 4e-7 or less, which is negligible (§4.5).

**Cycle timing** (controller on CPU1, SCHED_FIFO 80, GC disabled during the loop)

| Condition | Jitter p50 / p99 / max | Over 1.5 ms | Policy compute p50 | PDO round trip p50 |
|---|---|---|---|---|
| `--sim`, **VQC-PL** | **1.2 / 4.1 / 4.7 µs** | 0 / 6000 | 130 µs | 352 µs (emulator Python) |
| `--sim`, VQC-PS | 1.8 / 22.9 / 76.6 µs | 0 / 6000 | 164 µs | 351 µs |
| CAN loopback, PD (virtual ESC on CPU0) | 1.4 / 24~44 / 811 µs* | 4~11 / 10000 | 44 µs | 933 µs |
| CAN loopback, VQC-PL | 184 / 480 / 851 µs | 79 / 10000 | 139 µs | 966 µs |

\* Measured before the virtual ESC was changed to real-time handling. After the change, policy compute plus the virtual ESC response (about 960 µs) exceeds 1 ms and the cycle slips. Most of this delay is the virtual ESC's Python processing. The real ESC firmware's processing time is estimated to be on the order of µs (not measured).

**Assessment**: On the same board, with the ESC emulator removed (`--sim`) and the PL policy in use, **1 kHz cycle jitter p99 is 4.1 µs, meeting the G2 criterion (< 20 µs)**. 1 kHz jitter with a real ESC on a real CAN bus was not measured (only RTT via CANable was measured, §4.9).

### 4.5 FPGA Implementation

![Figure 14. VQC core latency by HLS optimization stage](figures/png/fig14-hls-optimization.png)

**Figure 14. VQC core latency by HLS optimization stage**

| Stage | Change | Latency | Estimated clock | LUT / DSP (HLS estimate) | Key bottleneck |
|---|---|---|---|---|---|
| v1 | Baseline (BRAM state vector) | 15,343 cyc (153 µs*) | 14.5 ns ❌ | 36 % / 40 % | Memory ports, false dependencies |
| v2 | Complete partition + unroll 2 + DEPENDENCE | 12,462 cyc | 19.9 ns ❌ | 74 % / 51 % | Loop flattening creates real inter-qubit dependencies → II=27 |
| v3 | LOOP_FLATTEN off | 12,915 cyc | 14.5 ns ❌ | 61 % / 62 % | In-place update → II=15 |
| v4 | **ping-pong (out-of-place)** | 2,643 cyc (**26.4 µs**) | 8.84 ns ✅ | 66 % / 66 % | — (II=1 achieved) |
| v5 | Transcendental functions moved to PS (final) | 2,248 cyc (**22.5 µs**) | 8.84 ns ✅ | 40 % / 32 % | — |

\* Value converted at 100 MHz. For v1~v3 the estimated clock exceeds 10 ns, so they cannot actually run at 100 MHz.

| Bitstream (post place-and-route) | `can0.bit` | `vqc_can0.bit` (final) |
|---|---|---|
| WNS @ 100 MHz | (no PL logic) | +0.366 ns ✅ |
| LUT / FF | Nearly 0 | 15,404 (29.0 %) / 23,392 (22.0 %) |
| DSP / BRAM | 0 / 0 | 72 (32.7 %) / 2 (1.4 %) |

| Inference path measured (board, CPU1, SCHED_FIFO, 20,000 runs) | p50 | p99 | Max |
|---|---|---|---|
| **PL path — C driver** (features, cos/sin + registers + core + tanh) | **29.0 µs** | **29.8 µs** | 196 µs |
| PS C kernel (entire same computation) | 64.6 µs | 65.7 µs | 48 ms† |
| PL path — one call from Python (ctypes) | 99 µs | 115 µs | — |
| PS kernel — one call from Python (ctypes) | 109 µs | 141 µs | — |
| PL path — pure Python MMIO (numpy) | 746 µs | — | — |

- The PL vs PS output difference with trained parameters is at most 3.7e-7 (test vectors) / 3.9e-7 (random inputs), at the level of floating-point operation-order and rounding differences between the FPGA and ARM. In the 20,000-run C bench with synthetic weights, the difference was 0.
- PL is **2.2× faster** than PS, and with a 0.8 µs gap between p50 and p99 its **timing is very consistent**. PS has a 1.1 µs gap.
- The pure Python MMIO path is slow because each numpy element access costs several µs on the Cortex-A9. That is why a C driver (`vqc/vqc_pl_driver.c`) handling everything from pre-processing to post-processing in one call was written.
- † This appears to be a value hit by Linux real-time throttling (only up to 950 ms allowed per second) in a SCHED_FIFO benchmark that runs without sleeping. It does not apply to a control loop that sleeps every cycle.

### 4.6 Time Usage Within a 1 kHz Cycle

![Figure 5. Time usage within a 1 kHz cycle](figures/png/fig5-timing-budget.png)

**Figure 5. Time usage within a 1 kHz cycle (estimated budget; only policy compute time is measured)**

The expected cycle budget with a real ESC is as follows.
- Observation generation and policy call (Python, PL): about 130 µs
- CAN round trip is about 350~420 µs (estimate). The basis is as follows.
  - An 8-byte frame is 111~135 µs including bit stuffing, and a round trip needs 2.
  - ESC response processing takes about 10~30 µs.
  - Host-side overhead is about 115 µs (loopback single-socket round trip of 236 µs minus one frame time).
  - It was initially put at 250~300 µs, but that value omitted host overhead and was corrected.

The total is about 480~550 µs, which fits within 1 ms. Moving the control loop to C would cut the policy portion to 29 µs. However, **the real-ESC round trip and jitter over the PS CAN0 path were not measured.** The measured RTT via CANable (USB) is p50 1.81 ms, far exceeding this budget (§4.9).

### 4.7 CAN Physical Path Verification (`can0.bit`)

Sending one frame in normal mode (loopback off) without a transceiver gave the following result.
- **17 bit errors** occurred (`CAN_ERR_PROT_BIT`), followed by a transition to bus-off.
- Interpretation: while TX (JA1) was driving dominant, RX (JA2) read recessive because of the pull-up. In other words, **EMIO RX is connected to the actual pin.**
- With a transceiver connected, TX should loop back to RX so this error disappears, and communication should be established with the ESC's ACK (expected). In practice, the SN65HVD230 path did not work (§5.22).

| CAN test | Result |
|---|---|
| Controller loopback, single socket | 5000/5000, round-trip median 236 µs |
| Loopback, two-process ping-pong | RTT p50 482 / p99 644 µs, **loss 32/3000 (1.1 %)** |
| Normal mode, no transceiver | Bit errors → bus-off (expected behavior) |

### 4.8 Web Visualization — VQC Actuator Lab

An English website was built so the research can be understood hands-on (`website`, three.js 0.160 + Chart.js). It was served with a local server (`python -m http.server 8765`), then verified and screenshotted with headless Chrome (Playwright).

![Figure 16. Website landing screen](figures/png/fig16-site-hero.png)

**Figure 16. Website landing screen — PD + VQC control runs in real time in the background, moving the actuator**

| Section | Contents |
|---|---|
| Actuator | 3D model assembled from the project's 10 real STLs (housing, 16-pin ring, 15-lobe disc, eccentric shaft, output carrier). Exploded view, housing cutaway, part labels |
| System | Residual architecture (firmware PD + VQC feed-forward) and the control-rate hierarchy |
| Simulator | Runs the 1 kHz closed loop in the browser while varying policy, trajectory, and joint parameters. 3D joint and target (ghost), real-time position/error/torque plots, 24-random-joint head-to-head |
| Inside the VQC | Circuit diagram and real-time encoding angles, \|ψ\|² of the 64 basis states, ⟨Z₀⟩ and τ_ff gauges |
| FPGA · Results | HLS optimization, PL/PS latency, resources, VQC vs MLP conclusion, goal verdicts |
| Real hardware (added 2026-10-17) | The 2026-10-13 open-loop run from the raw log (commanded vs applied angle, phase current), CAN round-trip time vs the 1 ms period, the four CAN faults and the FIFO bug (§4.9, §5.21, §5.23) |
| Status | Measured on hardware / in simulation / not done |

**3D kinematics**: The assembly relationships were reconstructed by analyzing the STLs.
- The housing has 16 internal pins and the disc has 15 lobes.
- The input-shaft eccentricity is 1.25 mm, and from the eccentric section's length (4.9 mm) there is a single disc.
- When the motor rotates −15q, the disc orbits along the eccentric while rotating q about its own axis, and the output flange and link also rotate q.
- The MAD 5010 motor is not in the STLs, so it was drawn directly as a 14-pole-pair rotor.

![Figure 17. Exploded view of the actuator assembled from real part STLs](figures/png/fig17-site-actuator-exploded.png)

**Figure 17. Exploded view of the actuator assembled from real part STLs**

![Figure 18. Housing cutaway — cycloidal disc (red) and output flange](figures/png/fig18-site-actuator-cutaway.png)

**Figure 18. Housing cutaway — cycloidal disc (red) and output flange**

**Verifying the computation matches the research code**: The web JS implementation (`policy.js`, `sim.js`) was compared against the Python reference.

| Item | Result |
|---|---|
| Max policy output difference (20 observations) | VQC 1.4e-7, MLP 6.5e-8, model FF 0 |
| Closed-loop RMS (sinusoid 0.3 rad · 0.5 Hz, 4 s), JS / Python | PD 6.0093 / 6.0093, model FF 0.1662 / 0.1662, VQC 1.2159 / 1.2159, MLP 0.8107 / 0.8107 mrad |
| Console and page errors | None (no horizontal overflow at desktop 1600 px or mobile 390 px) |

The browser results match the PYNQ `--sim` results in §4.4 (6.01 / 0.17 / 1.21 mrad).

![Figure 19. Browser simulator — PD + VQC with a heavy joint (J 0.02), high friction (0.3 N·m), and 2 ms delay](figures/png/fig19-site-simulator.png)

**Figure 19. Browser simulator — PD + VQC with a heavy joint (J 0.02), high friction (0.3 N·m), and 2 ms delay (two-sinusoid trajectory, RMS 1.29 mrad)**

![Figure 20. Inside the VQC circuit — real-time encoding angles and probabilities of the 64 basis states](figures/png/fig20-site-vqc.png)

**Figure 20. Inside the VQC circuit — real-time encoding angles and probabilities of the 64 basis states**

![Figure 21. Browser head-to-head — the same 24 random joints, 4 s sinusoidal trajectory](figures/png/fig21-site-compare.png)

**Figure 21. Browser head-to-head — the same 24 random joints, 4 s sinusoidal trajectory**

The browser head-to-head mean RMS was PD 6.85, model FF 0.78, **VQC 1.30, MLP (65) 1.04 mrad**. The sample (24 joints, one sinusoid type) is smaller than in §4.3, so the absolute values and model FF's ranking differ, but the ordering "PD only > VQC > same-size MLP" (by error) is the same. The VQC is much better than PD alone, and a similarly sized MLP is better than the VQC.

![Figure 24. Website real-hardware section — the 2026-10-13 open-loop run](figures/png/fig24-site-hardware.png)

**Figure 24. Website real-hardware section — the 2026-10-13 open-loop run (angles are commands, not measurements; CAN round trip vs the 1 ms period)**

### 4.9 Real-Hardware Open-Loop Drive — New ESC + CANable (2026-10-13)

After replacing it with a new B-G431B-ESC1, **the real actuator was moved for the first time.** However, **because there is no AS5600 encoder,** FOC (current control) and position control were not possible; only **open-loop drive** was performed, rotating the magnetic field to a commanded angle so the rotor follows. All angles below are **commanded values**, not measurements.

**Configuration**: PYNQ-Z2 → USB → CANable 2.0 (slcan firmware) → CAN 1 Mbps → B-G431B-ESC1 (open-loop firmware) → MAD 5010 + 15:1 reducer

| Test | Result |
|---|---|
| New board bring-up | SWD connection (STM32G431, 3.24 V), ST-LINK V2J28M18 → V2J48M35, option bytes, `FIRST_TIME_BOOTUP` two-flash passed |
| Encoder | None. Standard firmware waits forever in `Encoder_init` (I2C scan: 0 responding devices) → open-loop build (`OPENLOOP_NO_ENCODER`) written |
| Button/SWD-started open-loop drive | Output ±0.3 rad, 0.25 Hz, 1.0 V. All 3 runs (about 25 s, 40 s, 30 s) held mode, 0 errors, phase current max 1.20~1.27 A. **User visual confirmation: output shaft moved** |
| **PYNQ → CAN → ESC open-loop drive** | 20 s, 200 Hz, **4,000 commands, 0 dropped**. Phase current mean 0.80 A, max 1.37 A. IDLE after finish, 0 errors. **User visual confirmation: output shaft moved** |
| Real-bus RTT (via CANable) | **p50 1806 µs, p99 1966 µs, max 11011 µs** (5 s run without motor power: p50 1849, p99 1892, max 3392 µs) |
| Bus voltage (firmware-measured) | 13.54 V during PYNQ run, 13.81~14.05 V during SWD monitoring. User reported setting the PSU to 24 V → **mismatch, cause not identified** (§5.24) |

- Log: `results/logs/openloop_pynq_2026-10-13.csv` (commanded angle, applied angle, commanded voltage, phase current)
- The difference between the command and the applied angle returned by the firmware is at most 7.0 mrad. This is a communication timing offset: each reply carries the angle applied for the previous command (the peak commanded speed is about 7 rad/s at the motor, far below the firmware's 30 rad/s speed cap), and **it is not tracking error.**
- **The CANable path's RTT (about 1.8 ms) is longer than the 1 kHz control period (1 ms).** So the research's 1 kHz residual control cannot be done over this path. 1 kHz experiments need the PS CAN0 + SN65HVD230 path, which did not work this time (§5.22).
- Details: `besc1-firmware-bringup/MOVE_WITHOUT_CAN.md` §D, `besc1-firmware-bringup/CAN_SETUP.md` §5, `besc1-firmware-bringup/BOARD_REPLACEMENT.md` progress log

---

## 5. Troubleshooting Log

§5.1~5.8 are records from firmware bring-up (2026-09-20, 10-03; §5.7 includes content from 10-07 and 10-13), §5.9~5.19 are problems actually encountered during development on 2026-10-04~06, and §5.20~5.24 are from the new-ESC real-hardware work on 2026-10-13.

### 5.1 ST-LINK firmware compatibility ✅
**Symptom**: `DEV_USB_COMM_ERR` / `Unable to get core ID`. **Cause**: factory FW V2J28M18. **Fix**: upgrade to V2J48M35, then terminate the Java process.

### 5.2 BOOT0 pin latching ✅
After a hard reset the device enters the system bootloader. Fix: `STM32_Programmer_CLI -c port=SWD -ob nSWBOOT0=0 nBOOT0=1`.

### 5.3 `FIRST_TIME_BOOTUP` zero-struct save bug ✅
`storeConfig()` is called before `init()`, so a zero-filled struct is saved to Flash. Fix: `LOAD_*_FROM_FLASH=0`.

### 5.4 gcc 14.3 build errors ✅

### 5.5 Hard-coded absolute paths ✅

### 5.6 CLI connect does halt + reset ✅

(Details of 5.4~5.6 are in `besc1-firmware-bringup/README.md` §4.4~4.6)
Add `#include <stdio.h>`, change the linker script path to a relative path, and use `mode=Hotplug` when diagnosing.

### 5.7 ESC failure — a component overheated during soldering ❌ → ✅ (cause confirmed, replaced with a new board 2026-10-13)

![Figure 8. SWD no-response diagnosis and cause confirmation](figures/png/fig8-diagnosis-flow.png)

**Figure 8. SWD no-response diagnosis and cause confirmation**

- **Symptom (2026-10-03)**: Both SWD and JTAG failed to respond with `Unable to get core ID`. VTARGET was normal at 3.21~3.23 V.
- **Diagnosis at the time**: Software causes (RDP, NRST setting, SWD clock, ST-LINK firmware) and a power-stage incident were ruled out. The remaining hypothesis was G431 damage, with electrostatic discharge (ESD) presumed as the cause.
- **Cause (user report, 2026-10-07)**: **A component overheated while soldering on the board, causing the failure.**
  - Which component overheated and exactly when were not reported, so these are left as **unknown**.
  - It is consistent with the symptoms (ST-LINK normal, only the MCU side unresponsive), so this is judged to be the cause of the SWD no-response. The ESD hypothesis is rejected.
- **Why the diagnosis missed the cause**: The record at the time only confirmed "no history of power applied or motor connected → no electrical event"; **rework history such as soldering was not on the checklist.** Rather than spending time ruling out nine software hypotheses, the first question should have been "what physical work was recently done on this board?"
- **Actions**:
  - Since the overheated component and the extent of damage are unknown and damage around the MCU is possible, **board replacement is recommended**.
  - A new board must go through the bring-up procedure from scratch (ST-LINK upgrade, option bytes, `FIRST_TIME_BOOTUP` two-flash).
  - **New board purchased (user report, 2026-10-07).** The replacement procedure is laid out in 12 steps in `besc1-firmware-bringup/BOARD_REPLACEMENT.md`.
    - Key to the order: **before soldering, confirm SWD connection on USB alone → complete the firmware → then wire.** Establishing a "good through firmware" reference point first means any later problem can be narrowed immediately to the wiring/soldering work.
    - Each step has pass criteria and a work log table. It was carried out with the new board on 2026-10-13; steps 2~6 passed, and at step 7 it switched to an open-loop build because there was no encoder (§4.9, §5.20, `BOARD_REPLACEMENT.md` progress log).
  - While preparing the replacement procedure, the CAN wiring assumptions were corrected (§9.2).
    - The B-G431B-ESC1 **has an on-board CAN transceiver.** A transceiver (SN65HVD230) is needed only on the PYNQ side.
    - The ESC-side 120 Ω termination is switched by MCU pin CAN_TERM (PC14), and Recoil drives this pin LOW at initialization (`main.c:901`). The polarity was unknown at the time of writing, but on real hardware on 2026-10-13 it was judged that **PC14 HIGH = termination ON** (inferred from bus errors clearing, resistance not measured, §5.21).
    - The "J2 pin" and "SB18 solder bridge" in the earlier `CAN_SETUP.md` were unverified guesses. The CAN connector pin order (GND, CAN L, CAN H, 5V) is also from summary material and must be checked against the silkscreen.
- **v1.0 correction**: v1.0's "recovered by board replacement" was an assumption; there was no replacement record when v1.0 was written. The actual replacement was on 2026-10-13.
- **Recurrence prevention**:
  - Do not solder directly on the ESC; wire with connectors or crimp terminals.
  - If soldering is unavoidable, use a temperature-controlled iron (about 320~350 °C), work within 3 seconds per joint, and use flux and a heat-sink clip. Avoid pads around the MCU.
  - Immediately after the work, check the 3V3 rail for shorts and voltage, and check the SWD connection.
  - **Record the date and location of all hardware rework.**

### 5.8 Mistaking UART silence for a liveness signal ⚠️
Normal `MODE_IDLE` firmware sends nothing on USART2. Liveness must be judged only by SWD hotplug or CAN ping.

### 5.9 PS CAN0 not visible ✅ (correction of v1.0 description)
- **Symptom**: `can0` was absent from `ip link`.
- **Cause**: v1.0's "missing clock node" explanation was wrong. The default device tree already had `clocks` and `clock-names`; it was simply `status = "disabled"`.
- **Fix**: Applied an overlay that changes only `status`.
- **Additional problem and fix**: The reference clock was 8 MHz, giving too few tq per bit. The overlay raised clock 0x13 (can0) to 100 MHz. Loading a bitstream does not re-run `ps7_init`, so the clock must be set in the device tree.

### 5.10 No dtc or internet on the board ✅
The `.dtbo` was built on the PC with Python `fdt` and transferred. The board clock was also off (2026-05), so it was synced to PC time. With no RTC, it may drift again after reboot.

### 5.11 Windows Smart App Control blocking Vivado ✅
- **Symptom**: `0xC0E90002` on launch; the installer aborted with "An Application Control policy has blocked this file."
- **Cause**: Code Integrity events 3077/3118 recorded blocking of DLLs below the required signing level.
- **Fix**: The user turned off Smart App Control.
- **Note**: Defender's status value still showed `On` afterward, but no further actual block events occurred.

### 5.12 Vivado 2026.1 mandatory licensing ✅ (worked around)
- **Symptom**: From 2026.1, even the free (BASIC) tier will not start Vivado without a license file.
- **Cause**: The account's Product Licensing list was empty, and the file received was a license containing only the AI Engine feature.
- **Fix**: Installed **Vivado/Vitis HLS 2024.1**. It can target xc7z020 without a license and matches the board's PYNQ 3.1 version.

### 5.13 Mistaking a stale PDO response for the current one ✅
- **Symptom**: In the loopback test, the joint followed the reference about 250 ms late.
- **Cause**: The Recoil protocol has no sequence numbers. So once a response slips, every subsequent response is offset by one cycle. Also, in loopback mode the node receives its own transmitted frames.
- **Fix**: Flush the receive queue just before each request, and use the kernel `CAN_RAW_FILTER` so the host receives only device→host function codes. This handling is also needed with a real ESC.

### 5.14 Request backlog in the virtual ESC ✅
- **Symptom**: Even after the fix, the VQC run showed 28 mrad error.
- **Cause**: The Python virtual device advanced physics by 1 ms per frame; when processing fell behind, it processed the backlog of requests in order and kept falling behind.
- **Fix**: Changed it to respond immediately like the real firmware and to advance physics by wall-clock time.

### 5.15 Frame loss and missed responses in loopback mode ⚠️
About 1.1 % were lost in two-process ping-pong. The controller was changed to use the previous value on a single missed response and to stop after 5 consecutive misses. On the real bus, 0 of 4,000 frames via CANable were dropped (§4.9). The PS CAN path is not measured.

### 5.16 HLS pipeline II violation ✅
When the state vector was fully partitioned into registers, HLS ignored `DEPENDENCE false` and II became 15~27. **Separating the read array and the write array (ping-pong)** achieved II=1, and latency dropped from the 12,000-cycle range to 2,643 cycles (26.4 µs). In exchange, the PS C kernel slowed from 50 µs to about 64 µs because of the extra copy.

### 5.17 PL core gives wrong answers only on the board ⚠️ → avoided by architecture change
- **Symptom**: C/RTL co-simulation with the same test vectors PASSed (9.5e-7), but the PL core on the board had errors of up to 0.5.
- **Narrowing-down process**:
  - Identity-matrix gates with input 0 gave the correct answer.
  - With tanh input y at 0.1 or 20 (saturated) it was correct; it was wrong only in 0.25~1.0.
  - Reading the registers back returned exactly the values written.
  - Changing FCLK0 to 100, 50, and 25 MHz gave the same result, ruling out timing problems.
  - According to the synthesis log, the ROM initialization files were also read correctly.
- **Assessment**: The double-precision `exp` path used by HLS `tanhf` is believed to behave differently in RTL simulation and on real hardware. The root cause is **unresolved**.
- **Action**: tanh, cos, and sin were moved to PS, and PL computes only the state vector (§2.4). Results are in §4.2.

### 5.18 PYNQ `boot.py` overwrites PL at boot ✅
- **Symptom**: Right after reboot, the PL core did not respond (`ap_start` set but never completing), and 129 receive errors accumulated on `can0`.
- **Cause**: The PYNQ image's `bootpy.service` runs `boot.py` from the SD boot partition. This script loads `BaseOverlay("base.bit")` for LED blinking; it started at the same time as our service and finished **later** than our bitstream, overwriting the PL. There was also a problem that the service ran under `/bin/sh` and could not source the bash-only `pynq_venv.sh`.
- **Fix**: Added `After=bootpy.service` to the service and made it invoke the virtual environment's Python directly. After reboot, the following was confirmed.
  - Order: boot.py finished → `vqc_can0.bit` loaded → can0 up
  - PL output matches the reference within 2e-7
  - 0 can0 receive errors

### 5.19 Firmware gear ratio and torque units — found before real-hardware testing ✅
- **How it was found**: While preparing the real-hardware scenario, the firmware code was re-examined.
- **Firmware behavior**:
  - Recoil converts position as `encoder / gear_ratio` and current as `torque / Kt / gear_ratio`.
  - The default `gear_ratio` is 1, and with `LOAD_*_FROM_FLASH = 0` saved settings are not loaded either.
- **Problem**: The trained model uses "output-shaft angle + motor-shaft torque" units. Attached to real hardware as-is, position would have been in motor angle (15×), and gains and torque would have been off by 15×.
- **Fix**:
  - At startup, `run_controller.py` writes `gear_ratio = −15` and sends kp, kd, torque limit, and τ_ff scaled by 15 (firmware gains kp 300, kd 2.25). Measured torque is logged ÷15.
  - The emulator was also fixed to start at the default gear ratio 1 like the real firmware and to convert position and torque with the configured gear ratio.
  - Re-measured results were the same as v2.1 (`--sim` PD 6.01, model FF 0.17, VQC-PL 1.21 mrad, jitter p99 4.1 µs).
- **Addendum**: These gains give about 6× higher position stiffness than the Berkeley defaults (kp 50, kd 2). The first real-hardware test uses a small amplitude (scenario T5).

### 5.20 No encoder → firmware waits forever at initialization ⚠️ → open-loop build
- **Symptom**: After flashing the new board, mode = DISABLED, LED not blinking, no CAN or UART response. The call stack via SWD shows `MotorController_init → Encoder_init`.
- **Cause**: Recoil's `Encoder_init()` loops forever until the AS5600 (I2C1, PB7 SDA/PB8 SCL, 0x36) responds. An I2C bus scan added to the firmware found 0 responding devices, and the user confirmed there is no encoder.
- **Action**: Created an `OPENLOOP_NO_ENCODER` build (default 0, no effect on the standard build).
  - Skips the encoder wait and I2C reads.
  - In `MODE_VALPHABETA_OVERRIDE`, rotates the voltage vector by commanded angle × pole pairs. Voltage cap 2 V, angular speed cap 30 rad/s at the motor, output 0 if the bus is below 9 V.
  - Uses RPDO3 as [angle, voltage] → [applied angle, phase current magnitude].
  - Rejects modes that require an encoder.
- **Limitation**: Without position feedback, loss of synchronization cannot be detected. **The research's closed-loop experiments (G1, G5) absolutely require an encoder.**

### 5.21 CAN bus not working — four causes overlapping ✅ (CANable path)
- **Symptom**: With both adapters, the SN65HVD230 module and CANable, no frames passed to or from the ESC.
- **Diagnosis**: Read the ESC's FDCAN registers (ECR/PSR/RXF0S) directly over SWD, and had the ESC transmit frames (`fast_frame_frequency` in RAM) to check each direction separately.
- **Causes and fixes (in order)**:
  1. Poor contact on the ESC CAN pads → user soldered a pin header. SWD and firmware confirmed normal after soldering
  2. One CAN wire disconnected → reconnected
  3. **CANH/CANL swapped** → right after swapping, the ESC received a frame for the first time
  4. **No termination** → with PC14 LOW (upstream default), Bit1 errors and BUS-OFF; writing PC14 HIGH over SWD gave no errors. Judged **PC14 HIGH = ESC 120 Ω ON** (not a direct resistance measurement). Added firmware option `CAN_TERMINATION_ENABLED=1`
- **Lesson**: Changing common GND, polarity, and termination one at a time and checking with the error registers of the controllers on both sides was effective.

### 5.22 PS CAN0 + SN65HVD230 path not working ❌ (unresolved)
- The PYNQ's own transmissions went BUS-OFF with bit errors, and the ESC received nothing. Swapping TX/RX gave the same result.
- This test was done **before** fixing the ESC-side wiring problems in §5.21 above. However, bit errors (failing to read back its own signal) point to a module-side problem, so after the wiring fixes the module power (3V3), Pmod pin positions, and chip type (whether it is a 5 V-only TJA1050/MCP2551) must be rechecked.
- 1 kHz experiments need this path (§4.9).

### 5.23 ESC firmware RX FIFO backlog bug ✅ (fixed)
- **Symptom**: After the wiring fix, the ESC **received** pings (RXF0S put index incremented) but did not respond.
- **Cause**: While errors were piling up, 2 frames remained in RX FIFO0. The upstream `HAL_FDCAN_RxFifo0Callback` reads only 1 per interrupt, so every subsequent request was handled as **the frame from 2 earlier**.
- **Fix**: Changed the callback to read until the FIFO is empty. After that, `recoil_cli.py info 1` succeeded immediately.

### 5.24 Other real-hardware observations ⚠️
- **Bus voltage mismatch**: The user said the PSU was set to 24 V, but the firmware measured 13.54~14.05 V. Whether the cause is the PSU current limit, the actual setting, or the firmware divider coefficient (`(18+169)/18`) was not determined.
- **Running with `--start` right after flashing causes a HardFault** (CFSR 0x1400, MSP 0xFFFFFFD8). Doing a separate `-hardRst` works normally.
- **`make.exe` on this PC is blocked by the Windows Application Control policy** → build with `Recoil-Motor-Controller-BESC/demo/build_variant.sh` (calls gcc directly).
- **ST-LINK upgrade can be done from the command line**: `java -jar STLinkUpgrade.jar -sn <SN> -update`. It succeeded only right after re-plugging USB.

---

## 6. Goal Attainment

| # | Goal | Criterion | Actual result | Verdict |
|---|---|---|---|---|
| G1 | Single-axis FOC control | Mode switching and tracking | With the new ESC, CAN mode switching (IDLE → open-loop → DAMPING → IDLE on exit) and open-loop drive succeeded (PYNQ → CANable → ESC, 4,000 frames, 0 dropped). **No encoder, so FOC closed-loop and tracking not performed** | ⚠️ Partial |
| G2 | PYNQ real-time host | 1 kHz, jitter < 20 µs | `--sim` + VQC-PL: **p99 4.1 µs, max 4.7 µs** (met). With CAN loopback + Python virtual ESC, the cycle slips because of response delay (about 960 µs). Real ESC on a real bus (via CANable) RTT p50 1.81 ms, so **1 kHz not possible**; PS CAN path not working (§5.22) | ⚠️ Conditionally met |
| G3 | VQC PL implementation | Inference < 10 µs | Core 22.5 µs @ 100 MHz, full PL path 29 µs (2.2× vs PS), timing met, matches PS within 4e-7. **Misses 10 µs** | ⚠️ Partial |
| G4 | vs MLP | Error difference < 25 %, 50× parameter reduction | Same-size (65) MLP is 32 % more accurate than VQC. No gain vs the 4,673 MLP either | ❌ Rejected |
| G5 | sim-to-real | Apply to real hardware without retraining | Not performed (no encoder). 0~2 ms delay randomization included in training | ⏳ |

---

## 7. Multi-Joint Scaling — Reassessment Based on Measurements

The figures in v1.0 §7 (core 9.4 µs, CAN round trip 148 µs, 256 DSPs for 4-axis parallelism) were assumptions. Recalculated from measurements, they are as follows.

| Item | Measured/calculated | Implication |
|---|---|---|
| One PL core pass | 22.5 µs, DSP 72 (32.7 %) | Time-multiplexing 12 axes on a single core takes 12 × 22.5 = 270 µs, which fits within 1 ms. By DSP count, up to 3 cores (216/220) can be placed in parallel; splitting into 4-axis groups gives about 90 µs |
| CAN frame (8 bytes, 1 Mbps) | About 111 µs × 2 for round trip = 222 µs/axis | With a 1 kHz round trip per axis on a single 1 Mbps bus, about 4 axes is the limit. 12 axes need CAN FD or bus splitting (adding PS CAN1) |
| Policy size | A 65-parameter MLP was sufficient for this task | Whether VQC would be advantageous for multiple joints is an unverified hypothesis. It must be retested with an equal-budget control group |

---

## 8. Conclusions and Future Work

### 8.1 Conclusions

1. **A PYNQ-Z2-based 1 kHz control stack was completed on real hardware** (ESC via `--sim` and loopback HIL). Separately, **the real actuator was moved from the PYNQ over CAN with 200 Hz open-loop commands** (§4.9). The PS CAN0 → EMIO → Pmod bitstream, the Recoil protocol driver, and a real-time loop with safety monitoring all work.
2. **A VQC state-vector simulator was implemented in PL.** The core takes 22.5 µs at 100 MHz, and the full inference path on the board takes 29 µs, 2.2× faster than the PS C kernel, with output matching to float-rounding level. Jitter of the 1 kHz loop using the PL policy is p99 4.1 µs (`--sim`).
3. **The VQC feed-forward policy works but has no advantage.** Its error is about 6× smaller than with PD alone. However, **an MLP of the same size is more accurate**, so the research hypothesis that "a VQC is more parameter-efficient than an MLP" is **rejected** for this task.

### 8.2 Limitations

1. **Real-hardware closed loop not performed**: Open-loop drive was done with the new ESC, but there is no encoder, so all **control performance** is based on simulation or the emulator.
2. **Uncertainty in the joint model**: The parameters are estimates. System identification must be done on real hardware.
3. **1 kHz real bus not measured**: The real-bus RTT was measured only via CANable (USB) (p50 1.81 ms), and the PS CAN + SN65HVD230 path for 1 kHz did not work.
4. **Root cause of PL wrong answers unresolved** (§5.17).
5. **No quantum advantage**: 6 qubits can be fully simulated classically.

### 8.3 Future Work

| Priority | Task |
|---|---|
| 1 | **Mount AS5600 encoder + magnet** (SDA → H2/PB7, SCL → H3/PB8, `MOVE_WITHOUT_CAN.md` C.2.1) → `recoil_cli.py calibrate` with standard firmware → closed-loop test. ESC replacement (✅ 2026-10-13) is done |
| 2 | **Restore the PS CAN0 + SN65HVD230 path for 1 kHz** (§5.22: check module power, Pmod pins, chip type). CANable (RTT 1.8 ms) cannot do 1 kHz → staged real-hardware testing starting from `run_controller.py --policy pd --amp 0.05` (procedure, predictions, pass criteria: `actuator-vqc-control-report-scenario.md` T0~T9) |
| 3 | Identify joint parameters (J, b, τ_c) from real-hardware logs → retrain → real-hardware comparison of VQC, MLP, and model FF |
| 4 | Measure real-bus RTT, jitter, and loss over the PS CAN path (re-evaluate G2). The CANable path has been measured (§4.9) |
| 5 | Determine the cause of the board mismatch in HLS double-precision exp |
| 6 | Sweep qubit and layer counts (not performed this time) |

---

## 9. Appendix

### 9.1 Hardware Specifications

| Component | Specification |
|---|---|
| Motor | MAD 5010 110KV, 14 pole pairs, Kt = 0.1176 N·m/A |
| Reducer | Cycloidal 15:1 |
| Controller | B-G431B-ESC1 (STM32G431CB, Cortex-M4 @ 160 MHz) |
| Encoder | AS5600 12-bit (4096 CPR, firmware setting). **Not mounted for the 2026-10-13 real-hardware run** |
| FPGA SoC | TUL PYNQ-Z2, XC7Z020-1CLG400 (53,200 LUT / 106,400 FF / 220 DSP / 140 BRAM36) |
| CAN transceiver | SN65HVD230 (Pmod JA, not working §5.22) / **CANable 2.0** (USB, slcan, used for the 2026-10-13 real-hardware run) / ESC on-board transceiver (termination PC14 HIGH = ON, inferred from bus errors clearing, resistance not measured) |
| Development PC | Windows 11, 16 logical cores, 64 GB |

### 9.2 Firmware and CAN Settings

```
Firmware Version     : 0x20250226 (Recoil, MOTORPROFILE_MAD_5010_110KV)
FDCAN                : 1 Mbps, prescaler 16, seg1 7, seg2 2 -> sample point 0.80
Position loop        : 2 kHz, torque EMA alpha 0.27, torque_limit 1.0
Host gains (SDO)     : model kp 20 / kd 0.15 (output frame) -> firmware gear_ratio -15, position_kp 300, velocity_kp 2.25 (run_controller.py)
PYNQ can0            : xilinx_can, ref clk 100 MHz, tq 50 ns, sample point 0.80, restart-ms 100
Pmod JA              : JA1 (Y18) = CAN0_TX, JA2 (Y19) = CAN0_RX (pull-up), LVCMOS33
ESC CAN side         : on-board transceiver, FDCAN1 RX PA11 / TX PB9
ESC terminator       : 120 ohm via analog switch, CAN_TERM = PC14; HIGH = ON (inferred from bus errors, not measured); CAN_TERMINATION_ENABLED=1 drives HIGH
ESC CAN connector    : GND, CAN L, CAN H, 5V (summary of UM2516, verify on silkscreen; 5V not connected)
```

### 9.3 Reproduction Commands

```bash
# PC
python pynq-can/vqc/train.py --out vqc_params.json            # VQC (about 35 min)
python pynq-can/vqc/train.py --model mlp --hidden 8           # MLP control group
cd pynq-can/hls && vitis_hls -f run_hls.tcl && vitis_hls -f cosim.tcl
cd pynq-can/vivado && vivado -mode batch -source build_can0_overlay.tcl [-tclargs can_only]

# Website
cd website && python -m http.server 8765        # http://127.0.0.1:8765/
python website/tools/verify_site.py --shots       # verify + capture

# PYNQ (PY=/usr/local/share/pynq-venv/bin/python3)
$PY host/test_recoil.py
$PY host/vqc_pl.py ../overlay/vqc_can0.bit ../vqc/vqc_params.json
sudo taskset -c 1 $PY host/run_controller.py --sim --policy vqc --pl ../overlay/vqc_can0.bit
```

### 9.4 Related Documents

- `actuator-vqc-control-report-scenario.md`: closed-loop real-hardware test scenario after encoder mounting and 1 kHz CAN path restoration (prediction edition, measured columns left blank)
- `paper-vqc-actuator.md`: the same results written up in paper format
- `guide-for-beginners.md`: beginner's explanation (reflects v2.0)
- `besc1-firmware-bringup/README.md`, `CAN_SETUP.md`: firmware and CAN records
- `besc1-firmware-bringup/BOARD_REPLACEMENT.md`: new ESC replacement procedure and 2026-10-13 progress log
- `besc1-firmware-bringup/MOVE_WITHOUT_CAN.md`: moving without an encoder (demo and open-loop firmware, real-hardware results)
- `results/results.json`, `results/logs/`: raw data for this report
- `pynq-can/README.md`: implementation repository guide
- `website/README.md`: website (VQC Actuator Lab) guide

### 9.5 v1.0 Assumed Figures → v2.0 Measured Comparison

| Item | v1.0 (assumed) | v2.0~v2.4 (measured) |
|---|---|---|
| Control architecture | VQC produces entire torque | Residual: firmware PD + VQC feed-forward |
| Comparison MLP | 8-64-64-1 (4,801) | 6-8-1 (65), 6-64-64-1 (4,673), 3 seeds |
| VQC vs MLP | VQC +23.4 % worse, 66.7× reduction | Same-size (65) MLP has 32 % smaller error (VQC error 47 % larger), no reduction advantage |
| Inference latency | PL 9.4 µs | PL core 22.5 µs, PL path 29.0 µs, PS C 64.6 µs |
| Jitter | ±9 µs (PS CAN) | `--sim` + PL p99 4.1 µs, loopback + virtual ESC running concurrently p99 24~44 µs |
| CAN round trip | 148 µs | Loopback ping-pong p50 482 µs. Real ESC (via CANable USB) p50 1806 µs, p99 1966 µs |
| PL resources | DSP 64, LUT 22 % | DSP 72 (32.7 %), LUT 15,404 (29.0 %) |
| Qubit sweep, 10-qubit degradation | Results reported | Not performed |
| Real-hardware oscillation 8~12 Hz | Results reported | Real-hardware closed loop not performed (open-loop only). τ_prev feedback oscillation found and removed in simulation |
| Board replacement recovery | Reported | No record as of v2.0 (ESC failed because a component overheated during soldering). **Replaced with a new board on 2026-10-13, open-loop drive succeeded** (§4.9) |
