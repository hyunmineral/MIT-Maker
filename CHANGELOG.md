# Changelog

Development history up to the start of this repository. Dates are 2026. Document versions refer to the report
(`docs/actuator-vqc-control-report.md`).

## 2026-10-17 — repository baseline
- English documentation set (report v2.4, paper v2.2, guide v2.4, scenario S1.2) with all figures regenerated.
- Website: real-hardware section (2026-10-13 log, CAN round-trip vs 1 ms), corrected goals and status; tour video tool.
- Firmware build script compiles everything from source (image identical to the CubeIDE Release build).

## 2026-10-13 — first motion on real hardware
- New B-G431B-ESC1 brought up (ST-LINK upgrade, option bytes, two-stage first flash).
- No encoder fitted → `OPENLOOP_NO_ENCODER` firmware build (voltage-vector drive, RPDO3 = [angle, voltage]); button/SWD
  demo; I2C bus scan at boot.
- CAN made to work through a CANable 2.0 (slcan): pad header, loose wire, CANH/CANL swap, termination (PC14 high),
  and an RX FIFO backlog bug in the firmware (now drained). `SlcanTransport` added to `recoil.py`.
- Open-loop run from the PYNQ: 4,000 commands, 0 missed, RTT p50 1806 µs; output-shaft motion confirmed.
- PS CAN0 + SN65HVD230 path still not working.

## 2026-10-07 — failure cause and replacement plan
- The first ESC's SWD failure traced to a component overheated while soldering (ESD hypothesis rejected).
- Board replacement procedure, ESC CAN facts (on-board transceiver, PC14 terminator), test scenario with predictions.
- Firmware unit mismatch found before any hardware run: Recoil `gear_ratio` defaults to 1 → the host writes −15 and
  scales gains ×15.

## 2026-10-06 — prototype complete (software + FPGA)
- HLS core 15,343 → 2,248 cycles (22.5 µs @ 100 MHz) via out-of-place ping-pong updates; transcendentals moved to the PS
  after a board-only mismatch; C driver makes the PL path 29.0 µs vs 64.6 µs on the PS.
- `vqc_can0.bit` (CAN0 via EMIO to Pmod JA + VQC core), timing met; boot service ordering fixed.
- Policy comparison: VQC 1.43 mrad, MLP-65 0.98 mrad, MLP-4673 1.01 mrad, model FF 1.55, PD 8.79 → VQC efficiency
  hypothesis rejected. 1 kHz loop jitter p99 4.1 µs.
- Website "VQC Actuator Lab" (three.js + in-browser simulator).

## 2026-10-04 – 10-05 — PYNQ bring-up and host software
- PYNQ v3.1.1 image, direct Ethernet, PS CAN0 device-tree overlay, CAN loopback (5000/5000, RTT p50 482 µs).
- Recoil protocol driver, 1 kHz controller with safety monitor, byte-level firmware emulator, unit tests.
- Residual architecture chosen (pure VQC behaviour cloning of a PID reached R² ≈ 0.74); BC + BPTT training with
  domain randomization.

## 2026-10-03 — ESC unresponsive
- SWD/JTAG `Unable to get core ID` after two weeks in storage; nine software hypotheses ruled out.

## 2026-09-20 — firmware bring-up
- Recoil built and flashed on the B-G431B-ESC1: ST-LINK upgrade, BOOT0 option bytes, zero-struct store bug
  (`LOAD_*_FROM_FLASH = 0`), gcc 14 fixes, MAD 5010 110KV profile.
