# PYNQ-Z2 single-joint VQC controller — prototype

PYNQ-Z2 (PS: 1 kHz host loop, PL: VQC state-vector core) ⇄ CAN 1 Mbps ⇄ B-G431B-ESC1
(Recoil firmware, MODE_POSITION PD at 2 kHz) ⇄ MAD 5010 + 15:1 cycloidal.

```
 PYNQ-Z2 PS (Linux, SCHED_FIFO)                         B-G431B-ESC1 (Recoil)
 ┌─────────────────────────────────────────┐   RPDO3   ┌──────────────────────────────┐
 │ trajectory → ObsBuilder → VQC → tau_ff  │──[q_ref,──▶│ tau = kp(q_ref-q) - kd*qd    │
 │   PS: features, cos/sin, tanh (C)       │  tau_ff]  │       + tau_ff   (2 kHz)     │
 │   PL: 64-amplitude simulation → <Z0>    │◀─[q, tau]─│ EMA, clamp, FOC 10 kHz       │
 │ safety: err limit, DAMPING on any exit  │   TPDO3   └──────────────────────────────┘
 └─────────────────────────────────────────┘
```

Residual architecture: the firmware keeps the stabilising PD loop, the VQC supplies
feed-forward torque. Full write-up with all measurements:
`docs/actuator-vqc-control-report.md` (v2.4) — raw numbers in `docs/results/`.
Interactive visualisation (3D actuator + browser simulator of this controller): `website`.

## Layout
| path | what |
|---|---|
| `make_can0_dtbo.py`, `can0-enable.dtbo` | DT overlay: PS CAN0 `status=okay`, CAN ref clock 100 MHz |
| `can0-overlay.service`, `load_overlay.py` | boot: apply DT overlay → load `~/vqc_ctrl/overlay/active.bit` (after `bootpy.service`) → can0 up 1 Mbps, SP 0.8 |
| `can_loopback_test.py` | controller-internal loopback self test |
| `vivado/build_can0_overlay.tcl` | bitstream: CAN0 → EMIO → Pmod JA (JA1=TX Y18, JA2=RX Y19) [+ VQC core]; `-tclargs can_only` |
| `vivado/out/` | `can0.bit/.hwh`, `vqc_can0.bit/.hwh`, `xvqc_top_hw.h`, timing/utilization reports |
| `vivado/board_files/` | PYNQ-Z2 board files (XilinxBoardStore TUL/pynq-z2/A.0) |
| `hls/` | Vitis HLS top (`vqc_top.c`: cs[12] + W[192] → z), testbench, `run_hls.tcl`, `cosim.tcl` |
| `vqc/vqc_model.py` | circuit definition, numpy gate-by-gate reference, torch batched simulator |
| `vqc/vqc_kernel.c/.h` | float32 kernel shared by PS (`libvqc.so`) and HLS (`vqc_expval_z0_cs`) |
| `vqc/vqc_pl_driver.c` | /dev/mem driver for the PL core (pre/post-processing + registers in one call) |
| `vqc/vqc_runtime.py` | `VQCPolicy` (ctypes C kernel, numpy fallback) |
| `vqc/actuator_sim.py` | joint + firmware-loop model, observation builder, model feed-forward |
| `vqc/train.py` | BC init + closed-loop BPTT with domain randomization; `--model mlp --hidden 8` for baselines |
| `vqc/runs/` | VQC seeds 1–2, MLP 6-8-1 and 6-64-64-1 seeds 0–2 (params + logs) |
| `vqc/export_vectors.py`, `bench_kernel.c`, `bench_pl.c` | reference vectors, PS/PL timing benches |
| `host/recoil.py` | Recoil CAN protocol over SocketCAN (stdlib only) |
| `host/recoil_cli.py` | scan / info / mode / calibrate / get / set / store / watch |
| `host/run_controller.py` | 1 kHz controller (`--sim`, `--policy pd/model_ff/vqc/mlp`, `--pl bitfile`, `--gear-ratio -15`) |
| `host/virtual_recoil.py`, `host/recoil_emulator.py` | firmware emulator + simulated joint (unit tests, CAN loopback) |
| `host/vqc_pl.py` | PL policy (`VQCPolicyPL`, C fast path, same interface as `VQCPolicy`) |
| `host/analyze_log.py` | summarize / plot controller CSV logs |

On the board everything lives in `~/vqc_ctrl/{host,vqc,hls,overlay}`;
`PY=/usr/local/share/pynq-venv/bin/python3`. Board access: PC 192.168.2.1 ⇄ PYNQ 192.168.2.99, `ssh pynq`.

## Results (2026-10-06)

| | result |
|---|---|
| Policy, simulation (randomised plant, 256 eps) | PD 8.79 · model FF 1.55 · **VQC 1.43 ± 0.07** · MLP-65 0.98 ± 0.01 · MLP-4673 1.01 ± 0.01 mrad |
| HLS core (final, v5) | 2,248 cycles = **22.5 µs @ 100 MHz**, C/RTL cosim PASS (v4) |
| `vqc_can0.bit` | WNS +0.366 ns, LUT 15,404 (29 %), FF 23,392 (22 %), DSP 72 (33 %), BRAM 2 |
| Inference path, board, pure C (20k calls) | **PL 29.0 / 29.8 µs** (p50/p99) vs PS C kernel 64.6 / 65.7 µs |
| PL vs PS output | ≤ 3.9e-7 with trained weights (float rounding) |
| 1 kHz loop jitter, `--sim` + PL policy | p50 1.2 / p99 4.1 / max 4.7 µs |
| PYNQ tracking (0.3 rad, 0.5 Hz) `--sim` | PD 6.01 · model FF 0.17 · VQC 1.21 (PS = PL) mrad |
| CAN loopback + virtual ESC | PD 6.31 · model FF 0.38 · VQC-PS 1.45 · VQC-PL 1.38 mrad (loop overruns: Python virtual ESC ≈ 960 µs RTT) |
| CAN path | loopback 5000/5000; two-process ping-pong RTT p50 482 µs, 1.1 % loss; normal mode w/o transceiver → bit errors (pin path alive) |

## Not done — needs hardware
1. **ESC**: replaced on 2026-10-13 (the first board died from soldering heat). **No encoder is fitted**, so only the
   open-loop build runs (`Recoil-Motor-Controller-BESC/demo/recoil_openloop*.elf`). First real motion from the PYNQ:
   `host/openloop_run.py --channel /dev/ttyACM0` over a CANable 2.0 (slcan) — 4000 frames, 0 missed, RTT p50 1.81 ms
   (too slow for 1 kHz). Fit an AS5600 (SDA→H2/PB7, SCL→H3/PB8) before any closed-loop run.
2. **Wiring** (still not working on 2026-10-13, see `docs/besc1-firmware-bringup/CAN_SETUP.md` §5): SN65HVD230 on Pmod JA (3V3 pin 6, GND pin 5, CTX→JA1, CRX→JA2); CANH/CANL/GND to the ESC CAN connector
   (the ESC has an on-board transceiver; do not connect its 5 V pin). Expect ≈ 60 Ω CANH–CANL: the ESC terminator is
   switched by PC14 (driven LOW by Recoil, polarity unverified — measure it).
3. **Real ESC run** (joint free, PSU current limit on). The overlay and can0 come up at boot:
   ```
   $PY host/recoil_cli.py scan && $PY host/recoil_cli.py info 1 && $PY host/recoil_cli.py calibrate 1
   sudo taskset -c 1 $PY host/run_controller.py --id 1 --policy pd  --amp 0.05
   sudo taskset -c 1 $PY host/run_controller.py --id 1 --policy vqc --amp 0.2 --log /tmp/vqc.csv
   sudo taskset -c 1 $PY host/run_controller.py --id 1 --policy vqc --pl ../overlay/vqc_can0.bit --log /tmp/vqc_pl.csv
   ```
   Then identify the plant (J, friction) from the logs, retrain, and compare VQC / MLP / model FF on hardware.

## Rebuild
```
python vqc/train.py --out vqc/vqc_params.json            # ~35 min CPU
python vqc/export_vectors.py vqc/vqc_params.json
cd hls && vitis_hls -f run_hls.tcl && vitis_hls -f cosim.tcl      # Vitis HLS 2024.1
cd vivado && vivado -mode batch -nojournal -source build_can0_overlay.tcl
# board: make -C ~/vqc_ctrl/vqc libvqc.so ; copy vivado/out/vqc_can0.* + xvqc_top_hw.h to ~/vqc_ctrl/overlay/
```

## Design decisions
- **Firmware units.** Recoil scales position by 1/gear_ratio and torque by gear_ratio, with default
  gear_ratio = 1 and no flash load. The controller writes gear_ratio = -15 and sends kp, kd, torque limit and
  tau_ff x15 (model units: output angle, motor-side torque). The emulator mirrors this; results are unchanged.
- Real-hardware test plan with predictions: `docs/actuator-vqc-control-report-scenario.md`
  (`vqc/predict_scenario.py`).
- **Residual instead of direct torque.** Pure VQC behaviour cloning of a PID explained
  only ~74 % of label variance; keeping the firmware PD for stability is also safer.
- **No `tau_prev` / high-gain error inputs** (chatter: dtau_rms 0.029 vs 0.0026).
- **Stale-reply guard.** Recoil has no sequence numbers; drain RX before each request + CAN filters.
- **Out-of-place state update in HLS** (ping-pong) → II = 1; in-place updates stalled at II 15–27.
- **Transcendentals on the PS.** The HLS tanh/exp(double) datapath passed C/RTL co-simulation
  but returned wrong values for mid-range inputs on the board; the PL now only does the
  state-vector part and a C driver does everything else in one ctypes call.
- **Boot order.** PYNQ's `bootpy.service` loads `base.bit`; our service runs after it, otherwise
  the PL gets overwritten.
- The PS CAN reference clock is set by the device-tree overlay (a bitstream load does not rerun ps7_init).
- Vivado/Vitis HLS **2024.1** (2026.1 needs a license file even for the free tier).
