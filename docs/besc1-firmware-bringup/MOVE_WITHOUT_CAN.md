# Moving the Actuator Now (Without CAN or the PYNQ)

> **Written**: 2026-10-07 · **Updated**: 2026-10-13 (new ESC installed, no encoder → button, SWD and PYNQ CAN drive succeeded with the §D open-loop firmware)
> The motor (MAD 5010) and the reducer (15:1 cycloidal) are not broken, so **they can be moved as long as there is a controller.**
> A, B and C have not been tried yet; **§D (open-loop firmware) was actually performed on 2026-10-13** (§D.2, §D.4.1). Record the results in the log table at the end of this document.

| Method | What you need | Motion | When |
|---|---|---|---|
| A. Turning by hand | Nothing | Check the output shaft rotates freely | Now |
| B. Stepping one position at a time with a power supply | Current-limited bench PSU, alligator clips | Motor 4.3° per step (output 0.29° per step) | Now (motor must be disconnected from the failed ESC) |
| C. **Demo firmware** (operated by button) | New ESC, USB, 24 V PSU, AS5600 encoder | One calibration revolution + output ±0.3 rad (±17°) sine back-and-forth | Right after Steps 1–7 of the new board replacement procedure |

**Recommendation**: A for now, C once the new board arrives. Do B only if you want to check that the motor windings and magnets are fine without any electronics.

---

## A. Turning by hand (now)

1. With the motor leads not connected to anything, slowly turn the output shaft (link) by hand.
2. What to check: whether it turns without catching, whether the motor rotor turns 15 times per output revolution (put a tape mark on the rotor), and how much play (backlash) there is.
3. If the 3 motor phase leads are **touching each other**, it feels stiff when turned (dynamic braking). This is normal, but keep the phase leads separated while checking.

---

## B. Stepping one position at a time with a power supply (now, without a controller)

Principle: When DC is passed through two phases, the rotor aligns with that magnetic field direction and stops. Changing which pair of phases is connected moves it one position to the next (6-step drive done by hand).

**Motor values** (`MAD_5010_110KV` in the firmware's `motor_profiles.h`): phase resistance 0.62 Ω, 14 pole pairs, calibration current 3 A.

1. **Disconnect the motor from the failed ESC.** If it stays connected, current leaks into the ESC's FET diodes. The failed board is already slated for disposal, so it is fine to detach the phase leads.
2. Set the PSU to **constant current 1.5 A, voltage 5 V or less**, with the output off. The resistance between two phases is about 1.24 Ω, so about 1.9 V appears at 1.5 A.
3. Change the connections in the order below, each time **turn the output on and let it align for 1–2 seconds → turn the output off → connect the next pair**.

| Step | + terminal | − terminal |
|---|---|---|
| 1 | A | B |
| 2 | A | C |
| 3 | B | C |
| 4 | B | A |
| 5 | C | A |
| 6 | C | B |

4. One step = 60° electrical = motor 60/14 ≈ **4.3°**, output ≈ **0.29°**. Doing the 6 steps 14 times (84 steps) gives one motor revolution, 24° at the output. It is easy to see with the mark on the rotor.
5. Reversing the order turns it the other way. It does not matter which phase is A.

**Caution**
- Always set a current limit. Applying a high voltage in constant-voltage mode will drive tens of amps.
- Do not pass current continuously for more than a few seconds at a time (winding heating 1.5² × 1.24 ≈ 2.8 W).
- This method has **neither position feedback nor control.** It only checks that the motor, magnets and reducer are mechanically sound.

---

## C. Demo firmware — moving it with the button (new board)

A build has been prepared that runs calibration and position control using only **the user button on the ESC board**, without CAN wiring or the PYNQ.

### C.1 What was changed

- A `DEMO_STANDALONE` block was added to `Core/Src/app.c`. The default in `motor_controller_conf.h` is **0** (normal build). The demo code is not included in the normal build (confirmed by symbols).
- Demo build: `Recoil-Motor-Controller-BESC/demo/recoil_demo_standalone.elf`
  - On this PC `make.exe` is blocked by the Windows application control policy (2026-10-07), so `demo/build_demo.sh` calls gcc directly to build. Only one file, `app.c`, changed, so the rest links the existing Release objects. Builds with no warnings, text 49,248 B (normal build 48,888 B).
- Behavior:

| Button | State | Motor | LED |
|---|---|---|---|
| (boot) | IDLE | Stopped | Slow blink (based on TIM3 settings, not measured) |
| 1st press (only when bus voltage > 9 V) | CALIBRATION, about 10 s | **Slowly one revolution forward → reverse** (output ±24°) | Fast blink, short on-time |
| 2nd press | POSITION | Centered on the start position, **output ±0.3 rad (±17°), 0.25 Hz sine**, amplitude ramps up over 2 s | Fast blink, half on-time |
| 3rd press | DAMPING 0.5 s → IDLE | Stops | Slow blink |

- Safety measures:
  - If tracking error exceeds 1.5 rad at the motor (0.1 rad at the output), DAMPING. This also stops the case where the motor phase order is reversed and it jumps away due to positive feedback.
  - Torque limit 0.3 N·m at the motor (about 2.6 A, at or below the 3 A calibration current).
  - The safety watchdog is refreshed by the demo loop every 5 ms. If the main loop stalls, it goes to DAMPING after 1 second.
- Gains (motor-side units, `gear_ratio` 1): kp 0.5 N·m/rad, kd 0.01 N·m·s/rad. Converted to the output side, that is kp 7.5, kd 0.15, set softer than the host controller (kp 20, kd 0.15).

### C.2 Simulation pre-check (`demo/sim_demo.py`)

These are the results of plugging the demo settings directly into the project's joint model (same randomization ranges as training). **These are not hardware results.**

| | Result |
|---|---|
| Nominal joint | Max error 12.6 mrad, RMS 8.6 mrad, max torque 0.02 N·m |
| 256 randomized joints | 0 stops (trips), worst max error 15.3 mrad (trip threshold 100 mrad), 0 torque saturations |

### C.2.1 AS5600 encoder wiring (investigated 2026-10-13)

The firmware uses I2C1 as **PB7 = SDA, PB8 = SCL** (`stm32g4xx_hal_msp.c`). On the B-G431B-ESC1 these two pins come out at the **Hall sensor/encoder terminals** on the back of the board.

| ESC Hall/encoder terminal | MCU pin | AS5600 module |
|---|---|---|
| **H2** | PB7 | **SDA** |
| **H3** | PB8 | **SCL** |
| **+5V** | — | **VCC** (check that the module supports 5 V input. Most AS5600 modules accept 3.3–5 V) |
| **GND** | — | **GND** |
| H1 | PB6 | Not connected |
| — | — | **DIR → GND** (direction becomes unstable if left floating), OUT·PGO not connected |

- The terminal order, per community reports, is **GND / +5V / H3 / H2 / H1**. ⚠ Be sure to confirm it from the board's silkscreen printing.
- The board's Hall input pull-ups (10 kΩ) alone may not be enough for I2C. That is why the SimpleFOC community recommends **adding 4.7 kΩ (or 2.2 kΩ) pull-ups** on SDA and SCL. If the module already has pull-ups, they may not be needed. Try without pull-ups first, and add them if the device does not show up in the scan.
- **Magnet**: Attach a diametrically magnetized magnet to the end of the motor shaft, aligned with the chip center, with a 0.5–3 mm gap (the range recommended by the AS5600 datasheet).
- These terminals may be solder pads. If you must solder, follow the rules in `BOARD_REPLACEMENT.md` §11 (ESC disconnected from USB and power, temperature-controlled iron, within 3 seconds per joint). If possible, solder a pin header first and connect with jumper wires after that.
- Check that the connection is correct with the demo firmware's I2C scan: `demo_status.ps1` → `found=[0x36]` means OK.

Sources: [ST community — B-G431B-ESC1 encoder connection](https://community.st.com/power-management-53/b-g431b-esc1-encoder-connection-problem-43650), [SimpleFOC — B-G431B-ESC1 beginner + I2C guide](https://community.simplefoc.com/t/b-g431b-esc1-beginner-guide-i2c-guide/515), [SimpleFOC — Hall pins thread](https://community.simplefoc.com/t/b-g431b-esc1-as5047p-no-readings-on-hall-pins-and-seeking-spi-locations/8035)

### C.3 Procedure

1. Complete **Steps 1–7** of `BOARD_REPLACEMENT.md` (establish the reference point with the normal firmware).
2. Connect the AS5600 encoder (**SDA = PB7, SCL = PB8**, I2C address 0x36) and the 3 motor phase leads (Step 10 of the same document, soldering rules in Step 11).
   - **If the encoder does not respond, the firmware waits forever at initialization (`Encoder_init`).** In that case the LED does not blink, and neither the button nor CAN responds (confirmed on the new board on 2026-10-13).
   - Status check: `powershell -File Recoil-Motor-Controller-BESC/demo/demo_status.ps1` (reads mode, bus voltage and position over SWD)
3. Flash the demo firmware. Running it immediately with `--start` caused a HardFault (2026-10-13), so do a separate hard reset.
   ```powershell
   & $PROG -c port=SWD -w 'Recoil-Motor-Controller-BESC/demo/recoil_demo_standalone.elf' -v
   & $PROG -c port=SWD -hardRst
   ```
4. Leave the joint free to rotate and apply **24 V with a 2 A current limit** to the XT30. Keep your hand on the PSU output button.
5. Button press 1 → calibration (the motor slowly turns one revolution and comes back). When it finishes, the LED returns to a slow blink.
   - If it does not move during calibration or stops immediately: check the encoder (I2C) connection and the bus voltage. If an encoder (I2C) error occurs, the firmware sets an error bit and switches to IDLE, turning off the drive. In that case the demo does not accept the 2nd button press (error ≠ 0). Power-cycle to start over.
6. Button press 2 → sine back-and-forth. Press 3 → stop.
7. When the demo is done, **re-flash the normal firmware** (`README.md` §6.3). PYNQ hardware tests are done with the normal firmware.

> Because `LOAD_CALIBRATION_FROM_FLASH = 0`, after a power cycle you start again from calibration.

---

## D. Open-loop firmware — without an encoder (2026-10-13)

Since there is no encoder (AS5600), a build was made that rotates the magnetic field to a commanded angle so the rotor **follows it like a stepper**. **Because the angle is not measured, this is not a control experiment.** Instead, it shows that the real path from the FPGA (PYNQ) → CAN → ESC → motor works, and lets communication timing be measured on the real bus.

### D.1 Changes (`OPENLOOP_NO_ENCODER`, default 0)

| File | Change |
|---|---|
| `motor_controller_conf.h` | `OPENLOOP_NO_ENCODER`, voltage limit 2.0 V (about 3.2 A at standstill), angle rate limit 30 rad/s at the motor (2 rad/s at the output), minimum bus voltage 9 V |
| `encoder.c` | Skips the encoder wait and I2C reads (position, velocity = 0) |
| `motor_controller.c` | In `MODE_VALPHABETA_OVERRIDE` (0x21), rotates the voltage vector by commanded angle × pole pairs (14) (reuses `MotorController_setFluxAngle`). Modes that need the encoder (calibration, position, velocity, torque, current) are rejected (`ERROR_INVALID_MODE`) |
| CAN RPDO3 | Received values **[target angle, voltage V]** → response **[actually applied angle (not measured), phase current magnitude A]**. Watchdog unchanged (DAMPING if no frame for 1 second) |
| `app.c` (when built together with the demo) | Button press 1 → open-loop sine (output ±0.3 rad, 0.25 Hz, 1.0 V, ramped up over 2 s), press again to stop |

Builds (none add warnings; normal build size unchanged at 48,888 B):

| ELF | Purpose |
|---|---|
| `demo/recoil_openloop.elf` | Driven over CAN (PYNQ) |
| `demo/recoil_openloop_demo.elf` | Driven by button + CAN also possible (**currently on the board**) |

`bash demo/build_variant.sh recoil_openloop_demo -DOPENLOOP_NO_ENCODER=1 -DDEMO_STANDALONE=1`

### D.2 Board check results (2026-10-13, new board)

- Initialization passed after flashing: **mode = IDLE, error = 0** (previously it stopped at DISABLED waiting for the encoder).
- The I2C scan found no devices (no encoder, as expected).
- Bus voltage read as 4.3 V → XT30 motor power not applied. Below 9 V the output voltage is held at 0.
- **First drive (same day, after applying XT30)**: bus voltage 9.26–9.36 V (not 24 V). Instead of the button, it was started by writing 1 over SWD to `demo_remote_press` (a RAM variable, ELF symbol).
  - It held mode 0x21 (open-loop) for about 25 seconds, with 0 dropouts (out of 47 samples).
  - The measured current i_q (projected onto a fixed frame) kept changing sign, max 1.27 A → the rotating field is turning and phase current is flowing. Errors 0.
  - Bus voltage minimum 9.0 V. Under load it can hit the 9 V threshold and the output may cut out momentarily → **recommend raising the PSU to 12–24 V**.
  - Stopping was also done remotely (→ DAMPING → IDLE, errors 0).
  - Whether the output shaft actually moved cannot be known over SWD (no encoder). It has to be checked visually.
- **Second drive (user: PSU raised to 24 V)**: the bus voltage read by the firmware was **13.81–13.95 V**. This does not match 24 V, so the voltage at the XT30 terminals needs to be checked against the PSU display or with a multimeter. Whether the firmware's divider coefficient `(18+169)/18` matches this board has not been verified yet either.
  - During 30 s + 10 s drives it held mode 0x21, with errors 0. Correctly parsing the 24 samples from the 10 s drive gave |i_q| max 1.20 A, with the sign continually changing. After remote stop, IDLE, errors 0.
  - **User visual confirmation: the output shaft moves** (2026-10-13). This is the first record in this project of driving the real actuator (open-loop, no encoder).
  - Third drive (30 s): all 72 samples mode 0x21, errors 0, bus 13.83–14.05 V, |i_q| max 1.20 A, IDLE after stop.
  - The monitoring script for the first 30 s drive had a bug in parsing the error line (it also matched "error" in the I2C scan line). So the values above are from the 10 s re-run.
- Remote start/stop: `STM32_Programmer_CLI -c port=SWD mode=Hotplug -w32 <demo_remote_press address> 1` (address from `arm-none-eabi-nm recoil_openloop_demo.elf | grep demo_remote_press`, 0x20000214 in the current build). Writing the same command once more stops it.

### D.3 Driving it with the button (no CAN needed)

1. Leave the joint free to rotate. The 3 motor phase leads must be connected.
2. Apply **24 V with a 2 A current limit** to the XT30.
3. ESC button press 1 → voltage and amplitude increase over 2 seconds, giving **output shaft ±17° back-and-forth**. Press again to stop.
4. Status check: `powershell -File demo\demo_status.ps1 -Elf recoil_openloop_demo.elf` (mode 0x21, bus voltage, i_q).

### D.4 Driving it over CAN from the PYNQ (after the CAN wiring problems are solved)

```
sudo taskset -c 1 $PY host/openloop_run.py --id 1 --amp 0.1 --voltage 0.8 --duration 10 --log /tmp/openloop.csv
```
- Takes the output shaft amplitude (rad), sends motor angle ×15, and sends [angle, voltage] at 200 Hz. At the end, DAMPING → IDLE.
- Output: round-trip time p50/p99, number of missed responses, phase current mean/max. If the phase current is 0, check the motor phase leads or the bus voltage.

### D.4.1 First PYNQ → CAN → ESC drive results (2026-10-13)

Run with a CANable 2.0 (slcan, `--channel /dev/ttyACM0`):
`openloop_run.py --amp 0.3 --freq 0.25 --voltage 1.0 --duration 20`

| Item | Result |
|---|---|
| Bus voltage | 13.54 V (measured by firmware) |
| Command frames (200 Hz, 20 s) | 4000, 0 missed |
| RTT | p50 1806 µs, p99 1966 µs, max 11011 µs |
| Commanded range / applied range | Output ±0.300 rad / ±0.300 rad. Max difference between commanded and applied angle 7.0 mrad (due to the firmware rate limit and latency, not tracking error) |
| Phase current | Mean 0.80 A, max 1.37 A |
| End of run | DAMPING → IDLE, errors 0 |

- Log: `docs/results/logs/openloop_pynq_2026-10-13.csv`
- The angles are **commanded values**. There is no encoder, so the actual angle was not measured.

### D.5 Limitations

- If the load torque exceeds the torque the voltage can hold, the rotor **slips (loss of synchronization)**. The firmware cannot detect this.
- When voltage is first applied, the rotor may jump to the nearest field direction by up to half an electrical cycle (motor ±12.9°, output ±0.86°).
- If voltage is left applied, current flows even at standstill and the motor heats up (about 1.6 A at 1 V).

## Log table

| Item | Result |
|---|---|
| A. Turning by hand: catching, 1:15 check, backlash | |
| B. Step movement: 6-step direction consistency, heating | |
| C. Calibration completed or not, time taken | |
| C. Sine back-and-forth: amplitude near ±17°?, vibration/noise | |
| C. Whether a trip occurred and the circumstances | |
| D. Open-loop button/SWD drive | 2026-10-13: 3 runs, mode 0x21 held, errors 0, phase current max 1.20–1.27 A, output shaft movement confirmed |
| D. Open-loop PYNQ CAN drive | 2026-10-13: 4,000 frames 0 missed, RTT p50 1806 µs, phase current mean 0.80 A, output shaft movement confirmed |
