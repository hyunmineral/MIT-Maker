# Roadmap

Open work in priority order. Each item lists what "done" means. Test procedures and predicted values for the
hardware milestones are in `docs/actuator-vqc-control-report-scenario.md` (T0–T9).

## M1 — Closed loop on the real joint

- [ ] **Fit an AS5600 encoder** with a diametric magnet on the motor shaft (0.5–3 mm gap).
      Wiring: SDA → H2/PB7, SCL → H3/PB8, VCC, GND, DIR → GND; add 4.7 kΩ pull-ups if the boot I2C scan finds nothing.
      *Done when* `recoil_demo_standalone.elf` reports `found=[0x36]` (`demo_status.ps1`) and the ESC reaches IDLE.
- [ ] Flash `recoil_normal.elf`, run `recoil_cli.py calibrate 1` (scenario T3). *Done when* `flux_offset` ≠ 0 and
      position follows the shaft by hand.
- [ ] PD-only tracking at small amplitude (`run_controller.py --policy pd --amp 0.05`, scenario T5).
- [ ] Decide whether calibration should persist (`LOAD_CALIBRATION_FROM_FLASH=1` after a valid `store`, avoiding
      the zero-struct bug).

## M2 — 1 kHz CAN path

- [ ] Bring up PS CAN0 → Pmod JA → SN65HVD230: verify the module's 3.3 V supply, Pmod pin positions (JA1 = TX,
      JA2 = RX, pin 5 GND, pin 6 3V3) and that the chip is a 3.3 V part (not TJA1050/MCP2551).
      *Done when* `recoil_cli.py scan` finds device 1 on `can0`.
- [ ] Measure RTT, jitter and loss at 1 kHz on the real bus (scenario T4; prediction 350–420 µs RTT). The CANable
      path (p50 1.81 ms) cannot run 1 kHz.

## M3 — The research comparison on hardware

- [ ] VQC feed-forward on the real joint, PS then PL (scenario T6–T7).
- [ ] System identification (J, viscous and Coulomb friction, efficiency) from logs; retrain VQC and MLP on the
      identified plant (scenario T8).
- [ ] Repeat VQC vs MLP vs model-FF on hardware with seeds and the same budget (report G4, G5).

## M4 — Open technical questions

- [ ] Bus voltage reads 13.5–14.1 V while the PSU was set to 24 V — measure at the XT30 and check the firmware
      divider `(18+169)/18`.
- [ ] Explain why the HLS double-precision tanh/exp datapath passed C/RTL co-simulation but was wrong on the board
      (report §5.17).
- [ ] Qubit/layer sweep (never run).
- [ ] Multi-joint scaling: time-multiplex the PL core, CAN FD or a second bus (report §7).

## Housekeeping

- [ ] Choose a license for the project's own code.
- [ ] CI: run `pynq-can/host` unit tests, `docs/tools/check_docs.py` and the website self test on push.
- [ ] Optional: replace the vendored firmware tree by a git submodule of upstream Recoil + `LOCAL_CHANGES` patch.
