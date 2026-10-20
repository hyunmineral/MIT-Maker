# Real-Hardware Test Scenario — After Motor-Controller Recovery (Prediction Edition)

**Project**: Berkeley Humanoid Lite actuator control + FPGA acceleration of the VQC policy
**Date**: 2026-10-06
**Document version**: S1.2 (scenario · predictions · reflects real-hardware status as of 2026-10-13)
**Companion document**: `actuator-vqc-control-report.md` v2.4 (measured)

> 🧪 **Nature of this document — read this first**
> - This document **assumes that "the B-G431B-ESC1 has been replaced with a new board and the CAN transceiver has been wired,"** and compiles the **procedures, pass criteria, and predicted values** for the real-hardware tests to be done after that.
> - **All numbers in this document are predictions.** There is not a single measured value.
> - The basis of each prediction is marked.
>   - **[sim]**: Computed with the joint and firmware models used in training, over 200 randomly sampled joints
>   - **[calc]**: Computed analytically from CAN frame lengths, etc.
>   - **[board-measured, extrapolated]**: Values measured on the PYNQ-Z2, carried over to real-hardware conditions
> - **The "Measured" columns are intentionally left empty.** They will be filled in after the tests, compared with the predictions, and turned into report v3.0 (§8).
> - Measured results are in the report (v2.1 onward, currently v2.4). No number in this document may be copied into the report as a "result."

---

## 1. Prerequisites

> 📍 **Status as of 2026-10-13** (measured, report §4.9): P1 ✅ new ESC replaced and bring-up passed. **P3·P4 (PS CAN0 + SN65HVD230 path) ❌ not working.** Instead, communication was established over the CANable 2.0 (USB) path, but with an RTT p50 of 1.81 ms it is **insufficient for the 1 kHz scenarios (T5 onward)**. ESC termination was judged to be PC14 HIGH = ON (estimated from errors clearing). **Because there is no encoder (AS5600), steps from T3 (calibration) onward cannot proceed.** Only open-loop drive (communication and mode switching at the T1–T2 level) was confirmed.

| # | Prerequisite | How to verify |
|---|---|---|
| P1 | **Replaced with a new B-G431B-ESC1** (new board purchased, 2026-10-07). The previous board failed because a component overheated during soldering | Pass steps 2–7 of `besc1-firmware-bringup/BOARD_REPLACEMENT.md`. Key point: connect via SWD over USB only, before any soldering |
| P2 | Recoil 0x20250226 flashed. `MOTORPROFILE_MAD_5010_110KV`, `DEVICE_CAN_ID 1` | Procedure in `besc1-firmware-bringup/README.md` §6 |
| P3 | SN65HVD230 module wired to Pmod JA: 3V3 = pin 6, GND = pin 5, CTX ← JA1, CRX → JA2. The ESC has a built-in transceiver, so only CANH·CANL·GND go to the ESC CAN connector (**5V pin not connected**, check pin order against the silkscreen). **On the ESC side, connect with a connector or crimp terminals, without soldering** | Replacement procedure §8–9. CANH–CANL ≈ 60 Ω (module 120 Ω + ESC 120 Ω). ESC termination is PC14 HIGH = ON (2026-10-13, estimated from bus errors clearing), firmware `CAN_TERMINATION_ENABLED=1` |
| P4 | PYNQ-Z2 boots with `vqc_can0.bit` + `can0` (1 Mbps, SP 0.8) | `ip -d link show can0` → ERROR-ACTIVE |
| P5 | Start the 24 V bench PSU with a 2 A current limit; the joint can rotate freely; keep the mass at the end of the link small | Visual check |
| P6 | Emergency stop: keep the PSU output OFF button within reach | — |

---

## 2. Settings you must know — gear ratio and units

While preparing the scenario, we re-checked the firmware code and found settings that must be matched on real hardware (report v2.1 §5.19).

- **The firmware converts position and torque by the gear ratio.**
  - position = encoder / `gear_ratio`
  - current command = torque / Kt / `gear_ratio`
- **The default value stays in place.** The default value of `gear_ratio` is **1**. The current build has `LOAD_*_FROM_FLASH = 0`, so even settings stored in Flash are not loaded at boot.
- **The units differ from the training model.** The training model uses "output-shaft angle + motor-shaft torque" units.
- **Solution**: At startup, `run_controller.py` sets and converts the following (default `--gear-ratio -15`, same sign as `motor_configuration.json`).

| Item | Model value | Value sent to firmware |
|---|---|---|
| `gear_ratio` | — | −15 |
| `position_kp` | 20 | **300** (×15) |
| `velocity_kp` | 0.15 | **2.25** (×15) |
| `torque_limit` | 1.0 | **15** (×15, output-shaft N·m) |
| τ_ff (RPDO3) | policy output | ×15 |
| Measured torque (TPDO3) | — | logged after ÷15 |

- **Verification**: We also put this conversion into the emulator, exactly the way the real firmware does it. It starts at the default gear ratio of 1 and converts position and torque using the configured value. Rerunning in that state gave the same results as v2.1 (nominal joint, `--sim` 0.3 rad · 0.5 Hz: PD 6.01, model FF 0.17, VQC-PL 1.21 mrad, jitter p99 4.1 µs. The conditions differ from the 256-random-joint evaluation values of 8.79/1.55/1.43 mrad).
- **Note**: The Berkeley default settings (`motor_configuration.json`) are kp 50, kd 2 (output-shaft units). This project's gain (kp 300) gives about 6 times higher position stiffness. The first test starts with a small amplitude (§4 T5).

---

## 3. Test setup

```
PYNQ-Z2 ── Pmod JA ── SN65HVD230 ══ CANH/CANL (120 Ω ··· 120 Ω) ══ B-G431B-ESC1 ── MAD 5010 + 15:1 + link
   │                                                                    │
   └─ 192.168.2.99 (ssh pynq)                                  24 V PSU (starting at 2 A limit)
```

| Signal | PYNQ-Z2 | SN65HVD230 module | ESC |
|---|---|---|---|
| Power | Pmod JA pin 6 (3.3 V) / pin 5 (GND) | VCC / GND | Common GND |
| TX | JA1 (Y18) | CTX (D) | — |
| RX | JA2 (Y19) | CRX (R) | — |
| Bus | — | CANH / CANL | CANH / CANL |

---

## 4. Test procedures and predictions

Each step proceeds only after the previous step's pass criteria are met. Commands are run in `~/vqc_ctrl/host` on the board (`PY=/usr/local/share/pynq-venv/bin/python3`).

### T0. New ESC bring-up and flashing
- Because this is a new board, follow steps 2–7 of `besc1-firmware-bringup/BOARD_REPLACEMENT.md` (the underlying commands are in `besc1-firmware-bringup/README.md` §4·§6).
  1. Check the ST-LINK firmware.
  2. Set the option bytes (`nSWBOOT0=0 nBOOT0=1`).
  3. Go through the `FIRST_TIME_BOOTUP` two-flash procedure.
  4. Leave `LOAD_*_FROM_FLASH=0`.
- **Pass**: verify OK. After a normal boot, USART2 should be silent; that is normal (report §5.8).

### T1. Bus connection check
```
ip -d -s link show can0            # ERROR-ACTIVE, berr-counter 0/0
$PY recoil_cli.py scan             # devices: [1]
```
- **Prediction**: Device 1 responds and bus errors are 0.
  - Basis **[board-measured, extrapolated]**: Transmitting without a transceiver produced bit errors, so the pin path is alive. Once the transceiver loops TX back to RX and the ESC sends an ACK, the errors go away.
- **Troubleshooting order on failure**:
  1. CANH–CANL termination resistance (≈ 60 Ω). If ≈ 120 Ω, ESC termination may be off (PC14 HIGH = ON, firmware `CAN_TERMINATION_ENABLED`) → replacement procedure §9
  2. ESC CAN connector pin order (silkscreen) and swapped CANH·CANL
  3. Crossed TX·RX wiring
  4. Transceiver 3.3 V power
  5. Bit rate and sample point (1 Mbps, 0.8)

### T2. Status check
```
$PY recoil_cli.py info 1
```
| Item | Prediction | Measured |
|---|---|---|
| firmware | 0x20250226 | |
| mode | IDLE | |
| error | 0x00000000 | |
| bus_voltage | PSU voltage ±0.5 V | |
| gear_ratio | **1.0** (firmware default, §2) | |

### T3. Electrical-angle calibration
```
$PY recoil_cli.py calibrate 1      # the motor turns slowly — leave the joint free
$PY recoil_cli.py store 1
```
- **Pass**: Returns to IDLE within 60 s, error = 0, and `flux_offset` is nonzero (record the value).
- **Caution**: Because `LOAD_CALIBRATION_FROM_FLASH = 0`, **the calibration is lost when power is cycled.** Choose one of the following.
  - Redo T3 on every boot.
  - Store a correct value, then rebuild with `LOAD_CALIBRATION_FROM_FLASH = 1`. To avoid the zero-filled struct bug (report §5.3), always do `store` after calibration first, and only then make the change.

### T4. Communication timing (stationary, PD)
```
sudo taskset -c 1 $PY run_controller.py --id 1 --policy pd --amp 0 --duration 10
```
| Item | Prediction | Basis | Measured |
|---|---|---|---|
| PDO round trip p50 | **350–420 µs** | [calc] see below | |
| PDO round trip p99 | < 500 µs | [calc] | |
| Period jitter p99 | **< 20 µs** (G2) | [board-measured, extrapolated] `--sim` 4.1 µs; no virtual ESC sharing the CPU | |
| Missed replies | 0 / 10,000 | [board-measured, extrapolated] The 1.1 % loopback loss is presumed to be a characteristic of loopback mode. Recoil has automatic retransmission disabled, so any real-bus loss will show up as-is | |
| Periods over 1.5 ms | 0 | [calc] total about 480–550 µs < 1 ms | |

**Basis for the round-trip time [calc]**
- An 8-byte standard frame is 111 bits plus up to about 24 stuff bits, i.e., 111–135 µs. A round trip requires 2 of them.
- ESC response handling (FDCAN receive interrupt → processing → transmit) is about 10–30 µs.
- PYNQ-side overhead is about 115 µs. This is the 236 µs loopback single-socket round trip minus the time of 1 frame.
- The 250–300 µs written early in v2.1 omitted the host overhead, so it was corrected in v2.1 as well.

### T5. First motion — PD only, small amplitude
```
sudo taskset -c 1 $PY run_controller.py --id 1 --policy pd --amp 0.05 --freq 0.5 --duration 8 --log /tmp/T5_pd.csv
```
- **Safeguards**:
  - If `--err-limit 0.3 rad` is exceeded, automatically switch to DAMPING → IDLE.
  - The firmware watchdog is 1 s.
  - Limit the PSU current to 2 A.
- **Pass**:
  - The direction must be correct. When q_ref increases, q must also increase; if it moves the opposite way, stop immediately.
  - There must be no oscillation.
  - The RMS must be within the predicted range.

| Item | Prediction (200 joints p10 / p50 / p90) [sim] | Measured |
|---|---|---|
| RMS error | 1.11 / **1.64** / 2.11 mrad | |
| Max error | see prediction file | |

### T6. Policy comparison — the core experiment of the real-hardware edition

Run PD, PD + model FF, PD + VQC(PS), PD + VQC(PL), and PD + MLP on the same trajectory. Repeat each condition 3 times.
```
for p in pd model_ff vqc mlp; do sudo taskset -c 1 $PY run_controller.py --id 1 --policy $p --amp 0.2 --freq 0.5 --duration 8 --log /tmp/T6a_${p}.csv; done
sudo taskset -c 1 $PY run_controller.py --id 1 --policy vqc --pl ../overlay/vqc_can0.bit --amp 0.2 --freq 0.5 --duration 8 --log /tmp/T6a_vqc_pl.csv
# T6b: --amp 0.3 --freq 1.0      T6c: --traj chirp --amp 0.2 --freq 0.5 --duration 6
```
(`--policy mlp` uses the 65 weights in `vqc/runs/mlp_8_s0.json`. Checked with the emulator, it gave 0.81 mrad (nominal joint, default sine 0.3 rad · 0.5 Hz), the same as the website and the Python reference.)

**Predicted RMS error [mrad], p10 / p50 / p90 over 200 random joints [sim]**

| Test | PD only | PD + model FF | PD + VQC | PD + MLP(65) | Measured (PD / FF / VQC / MLP) |
|---|---|---|---|---|---|
| T6a sine 0.2 rad · 0.5 Hz | 3.50 / **4.31** / 5.03 | 0.13 / **0.44** / 0.91 | 0.53 / **0.67** / 1.28 | 0.36 / **0.60** / 1.01 | |
| T6b sine 0.3 rad · 1.0 Hz | 9.81 / **11.39** / 13.04 | 0.34 / **1.05** / 2.07 | 1.11 / **2.21** / 3.73 | 0.51 / **1.41** / 2.93 | |
| T6c chirp 0.2 rad (0.5 → 3.5 Hz) | 15.42 / **17.75** / 20.13 | 0.83 / **1.92** / 3.16 | 10.81 / **12.34** / 14.35 ⚠️ | 2.27 / **3.25** / 4.23 | |

**What to read from the predictions**
1. **Ordering**: For T6a·T6b, the predicted order is PD ≫ VQC > MLP ≳ model FF. Whether v2.1's conclusion (a same-size MLP is more accurate than the VQC) holds on real hardware is the core question of T6.
2. ⚠️ **The VQC is predicted to degrade sharply on the chirp (T6c)** (12.3 mrad vs MLP 3.2 mrad). The end of the chirp (3.5 Hz) is outside the range of the training trajectories (0.2–1.5 Hz). The circuit function appears to generalize poorly to out-of-range accelerations. If the same holds on real hardware, it will be a new result: **vulnerability to inputs outside the training range**. The chirp must always be run with an error limit relative to PD (`--err-limit`).
3. **The real joint may be outside the model range.** If the real inertia and friction fall outside the model range (J 0.007–0.028, τ_c 0.05–0.40), the predictions for all learned policies may be off. In that case, this is checked in T8.

### T7. PL vs PS equivalence on real hardware
- **Prediction**: The RMS difference between PD + VQC(PL) and PD + VQC(PS) should be smaller than the difference between repeated runs under the same conditions.
  - Basis **[board-measured, extrapolated]**: The policy output difference is ≤ 3.9e-7, and in `--sim` the RMS matched to the second decimal place.
- **Prediction**: Policy computation time p50 is about 130 µs for PL and about 165 µs for PS (including the call overhead of the Python loop, [board-measured, extrapolated]; these differ from the C-path measured values of 29.0/64.6 µs). Period jitter is expected to be smaller on the PL side.

### T8. System identification
```
sudo taskset -c 1 $PY run_controller.py --id 1 --policy pd --traj chirp --amp 0.1 --freq 0.3 --duration 10 --log /tmp/T8_chirp.csv
```
- **Method**: Using q, estimated q̇·q̈, and measured torque from the log, fit `J·q̈ = 15·η·τ_m − b·q̇ − τ_c·tanh(q̇/0.05)` by least squares.
- **Pass**: R² > 0.9. Check whether the estimated J, b, τ_c fall within the training range.

| Parameter | Training range (nominal) | Measured estimate |
|---|---|---|
| J [kg·m²] | 0.007 ~ 0.028 (0.014) | |
| b [N·m·s/rad] | 0.02 ~ 0.10 (0.05) | |
| τ_c [N·m] | 0.05 ~ 0.40 (0.20) | |
| η | 0.75 ~ 0.92 (0.85) | |
| Delay [ms] | 0 ~ 2 (1) | |

### T9. Retraining and re-comparison (if needed)
- **Condition**: Proceed if T8 yields out-of-range values or if the T6 measured values fall outside the predicted p90.
- **Method**: Re-center the randomization ranges on the measured values and rerun `train.py`. One VQC run and one MLP run, 3 seeds each. Then repeat T6.

---

## 5. Pass criteria (real-hardware evaluation of goals G1–G5)

| # | Goal | Real-hardware pass criterion | Prediction | Measured verdict |
|---|---|---|---|---|
| G1 | Single-axis FOC control | Pass T1–T5 (scan, calibration, direction, no oscillation) | Expected to pass | |
| G2 | Real-time host | T4: 1 kHz, jitter p99 < 20 µs, 0 missed, 0 overrun periods | Expected to meet (p99 a few µs) | |
| G3 | VQC PL implementation | PL policy runs in the real-hardware loop, PL ≡ PS (T7) | Expected to meet (the 10 µs target was already missed in v2.1: 22.5 µs) | |
| G4 | Versus MLP | In T6, VQC error ≤ MLP × 1.25, and a 50× parameter reduction | **Expected not to meet**: a 50× reduction does not hold against a same-size (65) MLP. On the error criterion, T6a is 1.12× (0.67 vs 0.60, met), T6b is 1.57× (2.21 vs 1.41, not met) | |
| G5 | sim-to-real | Without retraining, T6 measured values within the predicted p10–p90 range | Uncertain (the joint model is an estimate) | |

---

## 6. Risks and responses

| Risk | Symptom | Response |
|---|---|---|
| Phase order / encoder direction error | T3 fails; in T5, q moves the opposite way or runs away | PSU OFF immediately. Check `MOTOR_PHASE_ORDER`, then restart from T3 |
| Gear ratio not set | q appears as the motor angle (15×), gains off by 15× | `run_controller.py` writes `gear_ratio = −15` at startup (§2). Confirm with `info` |
| High position stiffness (kp 300 in output-shaft units) | Link bounces stiffly, noise | Run T5 with a small amplitude. If needed, lower `--kp` and retrain with that gain |
| Real-bus frame loss | `missed replies` > 0 | Check termination and wiring. A single miss holds the previous value; 5 consecutive misses trigger an automatic stop |
| Calibration lost | Torque behaves abnormally after reboot | Repeat T3 or `LOAD_CALIBRATION_FROM_FLASH = 1` (§4 T3) |
| VQC performance collapse on the chirp | Error spikes (predicted 12 mrad) | `--err-limit`. Record it as a result (generalization outside the training range) |
| Overheating (during operation) | Motor/ESC temperature rises | Keep each test to 10 s or less, cool down between tests |
| Soldering overheating (during wiring work) — **the actual cause of the previous board's failure** | No SWD response after the work, 3V3 abnormal | Do not solder onto the ESC; connect with a connector. If unavoidable, use a temperature-controlled iron, 3 seconds or less per joint, with a heat-sink clip. Check the 3V3 rail and SWD right after the work. Keep a work log |

---

## 7. Summary of predicted values (one page)

| Item | Prediction | Basis |
|---|---|---|
| Device scan | [1] | Protocol implementation, emulator tests |
| PDO round trip p50 | 350–420 µs | [calc] |
| 1 kHz jitter p99 | < 20 µs (a few µs expected) | [board-measured, extrapolated] 4.1 µs |
| T5 PD 0.05 rad RMS | 1.64 mrad (1.11–2.11) | [sim] |
| T6a VQC / MLP RMS | 0.67 / 0.60 mrad | [sim] |
| T6b VQC / MLP RMS | 2.21 / 1.41 mrad | [sim] |
| T6c VQC / MLP RMS | 12.34 / 3.25 mrad ⚠️ | [sim] outside training range |
| PL ≡ PS | RMS difference < run-to-run variation | [board-measured, extrapolated] |

Raw data: `docs/results/scenario_predictions.json` (generated by `pynq-can/vqc/predict_scenario.py`, 200 joints, seed 11)

---

## 8. How to turn this into report v3.0 after measurement

1. **Organize logs**: Copy each test's log (`/tmp/T*.csv`) to `docs/results/hw/` and summarize it with `host/analyze_log.py`.
2. **Fill in the tables**: Fill in the "Measured" columns of this document and mark whether each value is within the predicted range (p10–p90).
3. **Update the report**:
   - Add "4.10 Closed-loop real-hardware results" to report §4 (§4.9 holds the 2026-10-13 open-loop results).
   - Update the goal evaluation in §6.
   - Replace "Real motor drive: open-loop only succeeded" in the summary table with the closed-loop results.
4. **Update raw data and figures**: Add the measured constants to `docs/tools/collect_results.py`, and regenerate the figures, docx, and pptx.
5. **Update the website**: Change "Not done yet" in the Status section and update `website/data/results.json`.
6. **Items where the prediction was wrong**: Add the cause (joint model, bus, firmware setting) to the troubleshooting history in §5.
