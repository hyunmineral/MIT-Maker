# B-G431B-ESC1 Board Replacement Procedure

> **Written**: 2026-10-07 · **Situation**: The original board failed because a component overheated during soldering (user report, top of `README.md` · report §5.7). The user has **purchased a new B-G431B-ESC1**.
>
> - This document is the sequence for taking the new board to the state where **"the Recoil firmware is running and it can talk to the PYNQ-Z2 over CAN"**. Hardware testing then continues from T1 in `../actuator-vqc-control-report-scenario.md`.
> - Each step has a **pass criterion**. If it does not pass, do not move on to the next step.
> - **Performed with the new board on 2026-10-13** (results in the §12 work log and progress log). At the time of writing (10-07) it had not been performed; the commands and settings are the ones that actually succeeded on the original board (`README.md` §4·§6), but the results on the new board must be filled into the §12 work log.
> - **⚠ marks an unverified fact** (found in public sources but not directly confirmed in this project). Be sure to check it on the actual hardware.

---

## 0. At a glance

| Step | Content | Pass criterion | Soldering |
|---|---|---|---|
| 1 | Incoming inspection, isolate the failed board | No visible defects | — |
| 2 | Check it is alive with **USB only connected** | 3V3 LED lit, SWD connection succeeds | None |
| 3 | ST-LINK firmware upgrade | V2J45 or later | None |
| 4 | Option byte settings | `nSWBOOT0=0`, `nBOOT0=1` | None |
| 5 | Check build settings | 4 settings match, build succeeds | — |
| 6 | Flash `FIRST_TIME_BOOTUP` twice | verify OK both times | None |
| 7 | Check operation (SWD Hotplug) | PC changes within the app region (0x0800xxxx) | None |
| 8 | CAN wiring | Pin order checked on silkscreen, 5 V not connected | **Connector on the ESC side** |
| 9 | Termination resistance measurement | CANH–CANL ≈ 60 Ω | — |
| 10 | Connect motor phase leads and power | Re-check of Steps 2·7 passes after the work | §11 rules if needed |
| 11 | Soldering rules (preventing a repeat failure) | — | — |
| 12 | Work log → scenario T1 | Log filled in | — |

**Core principle**: Finish the firmware first (Steps 2–7, no soldering), and do the wiring afterwards. That way, if a problem appears after wiring or soldering, you still have a reference point that "the board was fine to begin with". The original board had no such reference point, so diagnosing the cause took time (`README.md` §4.9).

---

## 1. Incoming inspection and isolating the failed board

1. Before taking the new board out of the anti-static bag, touch grounded metal or wear a wrist strap.
2. Inspect the exterior. There must be no missing components, scorch marks, or bent pins.
3. **Put a `FAULTY – soldering overheat 2026-10` label on the failed board** and store it separately. If the two boards get mixed up, the diagnosis gets tangled again.
   - Do not reconnect the failed board to the same PC or the same power supply as the new board (there may be components shorted by the overheating).
4. Write the serial number or label on the back of the board into the §12 log.

**Pass criterion**: No visible defects.

---

## 2. Check it is alive with USB only (before soldering)

Check the new board first **with nothing soldered to it**. Do not connect the XT30 (motor power) either.

1. Connect it to the PC with a USB Micro-B cable. USB alone powers the MCU and ST-LINK at 3.3 V (`README.md` §3.2).
2. See whether the board's power LED lights up.
3. Check that the ST-LINK is visible in Device Manager or with the command below (VID 0483).
   ```powershell
   Get-PnpDevice -PresentOnly | Where-Object InstanceId -match 'VID_0483'
   ```
4. Check the SWD connection. For the environment variables, run `README.md` §6.1 first.
   ```powershell
   & $PROG -c port=SWD mode=Hotplug
   ```
   - On success, device information such as `Device ID : 0x468` (STM32G431/441 family) is shown. ⚠ Just record the exact ID value printed; if a different value appears, check the device name recognized by CubeProgrammer.
   - If you get `DEV_USB_COMM_ERR` or `Unable to get core ID`, do Step 3 (ST-LINK firmware) first **before concluding the board is faulty**. The factory firmware V2J28 does not work with the current CubeProgrammer (`README.md` §4.1).

**Pass criterion**: Power LED lit, ST-LINK recognized, (after Step 3) SWD connection succeeds.

> If SWD already fails at this step, **it is before soldering, so it is a dead-on-arrival defect**. Ask the seller for an exchange. Being able to make this judgment is the reason to "check before soldering".

---

## 3. ST-LINK firmware upgrade

Problem confirmed on the original board: the factory ST-LINK/V2-1 firmware (V2J28M18) could not communicate with STM32CubeProgrammer 2.23 (`README.md` §4.1).

```powershell
$java = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.jre.win64_3.4.300.202604201452\jre\bin\javaw.exe'
$jar  = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.stlink-gdb-server.win32_2.2.500.202604010938\tools\bin\STLinkUpgrade.jar'
Start-Process -FilePath $java -ArgumentList "-jar","`"$jar`""
```

1. In the GUI, click **Open in update mode** → **Upgrade**.
2. When it finishes, **be sure to close the window.** If the Java process remains, subsequent CLI communication is blocked.
   ```powershell
   Get-Process javaw, java -EA SilentlyContinue | Stop-Process -Force
   ```
3. Unplug the USB and plug it back in after 5 seconds (`README.md` §4.7).
4. Run the SWD connection from Step 2, item 4 again.

**Pass criterion**: ST-LINK firmware V2J45 or later, SWD connection succeeds.

---

## 4. Option byte settings

On the B-G431B-ESC1, the BOOT0 pin (PB8) can be held HIGH during a hard reset, so it may boot into the system bootloader. Recoil writes the option bytes but does not go as far as applying them (`OBL_LAUNCH`), so set them yourself (`README.md` §4.2).

```powershell
& $PROG -c port=SWD -ob displ                      # record current values (§12)
& $PROG -c port=SWD -ob nSWBOOT0=0 nBOOT0=1
& $PROG -c port=SWD -ob displ                      # confirm they changed
```

**Pass criterion**: `nSWBOOT0 : 0x0`, `nBOOT0 : 0x1`.

---

## 5. Check build settings

Firmware source: `Recoil-Motor-Controller-BESC/Recoil-Motor-Controller-B-G431B-ESC1`.
The local modifications (`README.md` §5) are already in the source, so **there is no code to change because of the new board.** Just check the settings below.

`Core/Inc/motor_controller_conf.h`:

| Setting | Value | Reason |
|---|---|---|
| `MOTORPROFILE_MAD_5010_110KV` | Defined (other profiles commented out) | This project's motor |
| `DEVICE_CAN_ID` | `1` | Host (`run_controller.py --id 1`) and scenario baseline |
| `LOAD_ID_FROM_FLASH` / `LOAD_CONFIG_FROM_FLASH` / `LOAD_CALIBRATION_FROM_FLASH` | All `0` | Avoids the zero-struct save bug (`README.md` §4.3) |
| `FIRST_TIME_BOOTUP` | `1` → `0` in Step 6 | See below |

Leave the already-applied gcc 14 fix (`#include <stdio.h>`), the makefile linker path, and `objects.list` as they are (`README.md` §4.4·§4.5).

```powershell
Set-Location 'Recoil-Motor-Controller-BESC/Recoil-Motor-Controller-B-G431B-ESC1/Release'
make clean
make -j8 all
```

**Pass criterion**: 4 settings match, build succeeds (`.elf` produced).

> **Good to know**: Because `LOAD_*_FROM_FLASH = 0`, the gear ratio (`gear_ratio`) and calibration **revert to defaults when power is cycled.** `run_controller.py` writes `gear_ratio = -15` at startup, and calibration must be redone every time power is applied (scenario §2·T3).

---

## 6. Flash `FIRST_TIME_BOOTUP` twice

A new MCU has an empty Flash configuration area. Follow exactly the sequence that succeeded on the original board.

1. In `motor_controller_conf.h`, change `FIRST_TIME_BOOTUP` to **`1`** and build.
2. Flash and run.
   ```powershell
   & $PROG -c port=SWD -w $ELF -v --hardRst --start
   ```
3. Wait a few seconds (the first-boot initialization routine runs).
4. Set `FIRST_TIME_BOOTUP` back to **`0`** and build again.
5. Flash again (same command as item 2).

**Pass criterion**: `File download complete` and successful verify both times.

> **Do not leave a build with `FIRST_TIME_BOOTUP = 1` on the board.** The initialization routine would run on every boot. Record in §12 that the last flashed build is `0`.

---

## 7. Check operation — with SWD Hotplug (not UART)

Recoil running normally **prints nothing** on USART2 (the COM port). A silent UART is not a sign of failure (`README.md` §4.8).

A default SWD connection resets the CPU, so use `mode=Hotplug` to observe the running state (`README.md` §4.6).

```powershell
& $PROG -c port=SWD mode=Hotplug --coreReg PC
& $PROG -c port=SWD mode=Hotplug --coreReg PC
```

**Pass criterion**:
- The PC is in the app region (`0x0800xxxx`), and the value must differ between the two reads (running, not stopped).
- If the PC is `0x1FFFxxxx`, it has booted into the system bootloader → re-check Step 4 (option bytes).
- If it stays at the HardFault handler address, check that `LOAD_*_FROM_FLASH` in Step 5 is 0.

> If you want to see the motor actually turn before CAN wiring, you can use the **demo firmware** (calibration and sine back-and-forth via the button) after Step 10 (encoder and motor connection) → `MOVE_WITHOUT_CAN.md` section C.

**A board that has passed up to here is the "firmware OK" reference point.** If a problem appears during later wiring work, come back to this step and run the same commands to compare.

---

## 8. CAN wiring (PYNQ-Z2 ↔ ESC)

### 8.1 Configuration

```
PYNQ-Z2 Pmod JA                SN65HVD230 module             B-G431B-ESC1 CAN connector
 pin6 3V3 ──────────────────── 3V3
 pin5 GND ──────────────────── GND ─────────────────────────── GND
 JA1 (CAN0 TX, Y18) ────────── CTX
 JA2 (CAN0 RX, Y19) ────────── CRX
                               CANH ══════ twisted pair ═════ CANH
                               CANL ══════ twisted pair ═════ CANL
                                                              5V  ✗ not connected
```

- **No transceiver is needed on the ESC side.** The B-G431B-ESC1 has an on-board CAN transceiver, so CANH/CANL come straight out of the connector. The MCU-side signals are FDCAN1 (RX = PA11, TX = PB9, firmware `stm32g4xx_hal_msp.c`).
- A transceiver (SN65HVD230) is needed **only on the PYNQ side**, because the PYNQ's PS CAN controller outputs only logic signals (TX/RX) (report §4.7, §5.9).
- The "J2 pin?" and "SB18 solder bridge" in the earlier document (`CAN_SETUP.md` §5) were unverified guesses. This document takes precedence.

### 8.2 ESC-side connector pin order — ⚠ check on the silkscreen

- According to public sources (a summary of the ST user manual UM2516), the CAN connector (J1) is a 4-pin connector in the order **GND, CAN L, CAN H, 5V**. ⚠ This project could not download the original PDF, so this has not been directly confirmed.
- **Before wiring, confirm the pin names from the board's silkscreen printing**, and use a multimeter to check that the GND pin has continuity with the USB connector shell (GND).
- **Do not connect the 5V pin.** The SN65HVD230 module is a 3.3 V part and takes 3.3 V from the PYNQ. Feeding 5 V into the module can damage the module and the Pmod pins.

### 8.3 Connection method — no direct soldering to the ESC

Because the original board failed from overheating during soldering (§11), connect **the ESC side without soldering**.

1. Use a mating connector for the ESC CAN connector, or jumper (Dupont) cables for pin headers.
2. Twist CANH/CANL together (twisted pair) and keep them short, within 30 cm.
3. Any part that needs soldering (such as the pin header on the SN65HVD230 module) is done separately **with the ESC disconnected**.
4. After wiring, secure the cables so there are no bad contacts (so they do not get pulled as the joint moves).

**Pass criterion**: Pin order confirmed on the silkscreen, 5V not connected, nothing soldered to the ESC (if unavoidable, follow the §11 rules and re-check Steps 2·7 immediately afterwards. On 2026-10-13 a pin header was soldered to the CAN pads and the re-check passed).

---

## 9. Checking the termination resistance

A CAN bus needs 120 Ω termination at both ends. In this configuration, the two ends are the SN65HVD230 module and the ESC.

| Location | Termination | Notes |
|---|---|---|
| SN65HVD230 module | Usually 120 Ω built in | Varies by module — confirm by measurement |
| B-G431B-ESC1 | 120 Ω, **switched on/off by an MCU pin (CAN_TERM = PC14)** | ⚠ See below |

**What is and is not confirmed about the ESC termination**:
- Confirmed: The firmware's `Core/Inc/main.h` defines `GPIO_CAN_TERM` = **PC14**, and `Core/Src/main.c:901` writes it **LOW** at initialization. Upstream Recoil does not change this pin afterwards (the local firmware drives it HIGH with `CAN_TERMINATION_ENABLED=1`).
- Public sources: The ESC termination connects 120 Ω via an analog switch, and per the truth table 120 Ω is connected when CAN_TERM is "ON".
- **2026-10-13 judgment: PC14 LOW = termination OFF, HIGH = ON.** Bit1 errors and BUS-OFF at LOW, no errors at HIGH (inferred from bus errors, not a direct resistance measurement). At the time of writing the polarity was unknown, so the measurement method below was written.

**Measurement method** (all power OFF, USB also disconnected):

1. With a multimeter in resistance mode, measure between CANH and CANL on the bus.
2. Interpretation:

| Measured value | Meaning | Action |
|---|---|---|
| ≈ 60 Ω | Two 120 Ω at both ends | Normal |
| ≈ 120 Ω | Only one end terminated | See explanation below |
| Several kΩ or more | No termination | Add 120 Ω on the module side |
| ≈ 0 Ω | Short circuit | Check wiring, do not apply power |

**In a power-off measurement the ESC termination may not be visible**, because the analog switch is likely open when unpowered. So measure twice.

1. Power-OFF measurement (table above) — mostly shows the module-side termination.
2. With **only USB connected to the ESC and the firmware running**, and the PYNQ and module powered off, measure CANH–CANL again.
   - If it drops to around 60 Ω, the ESC termination is on. (Upstream firmware leaves PC14 LOW, so according to the 2026-10-13 judgment, around 120 Ω should appear in this case.)
   - If it stays at 120 Ω, the ESC termination is off. With wiring within 30 cm and only two nodes, 1 Mbps often works with termination at one end only, but if bus errors occur in scenario T1, add 120 Ω at the end opposite the module (near the ESC connector) **on the connector side** (not soldered to the ESC).
   - Record the measurement result (polarity) in §12. Once this value is confirmed, the ⚠ in the document can be removed.

> The multimeter's measurement current flows through the transceiver, so an error of a few Ω is normal.

**Pass criterion**: ≈ 60 Ω in the operating state, or if ≈ 120 Ω, record that fact and judge by whether bus errors occur in T1.

---

## 10. Connecting motor phase leads and power, and re-checking after the work

1. Connect the **3 motor phase leads** (MAD 5010) and the **XT30 power lead**. Where possible, connect with connectors (bullet connectors, mating XT30).
2. **Encoder**: This firmware reads an external magnetic encoder, the **AS5600, over I2C** (`Core/Inc/encoder.h`, address 0x36). Move the existing encoder wiring to the same pins on the new board, and check the gap and alignment between the magnet on the end of the motor shaft and the AS5600. ⚠ This project has never recorded the encoder wiring, so photograph the connection locations on the original board before moving it (when removing cables from the failed board too, disconnect connectors rather than desoldering).
3. **Re-check immediately after the work** (do not apply XT30 power yet):
   - USB only connected → power LED lit (Step 2)
   - `& $PROG -c port=SWD mode=Hotplug --coreReg PC` → running in the app region (Step 7)
   - If either one fails, **the work you just did is the cause**. Do not go further; undo that work.
4. When applying XT30 power for the first time, start at **24 V with a 2 A current limit** and leave the joint free to rotate (scenario P5·P6).

**Pass criterion**: Steps 2·7 still pass after the work.

---

## 11. Soldering rules — preventing a repeat failure

The original board **failed because a component overheated during soldering** (component and timing unknown). These are the rules to prevent the same thing.

1. **Avoid soldering to the ESC board as much as possible.** Use connectors, crimp terminals, and jumper cables.
2. If you must solder:
   - Use a **temperature-controlled iron** set to about 330–350 °C for lead-free solder. For large pads (XT30, motor phase leads), switch to **a larger tip** rather than raising the temperature.
   - Work **within 3 seconds** per joint. If it does not melt, lift off, let it cool, add more flux, and try again.
   - Leave **cooling time** between joints. Do not heat the same area repeatedly.
   - Keep heat away from nearby small components (MCU, gate driver, current-sense circuit). Use a heat-sink clip if needed.
   - **Rework the same joint at most twice.** Beyond that, the pad and nearby components may be damaged.
   - Do not use a hot-air gun on the ESC board.
3. **After every soldering job, do Step 10, item 3 (re-check).** That way you know immediately which job caused a problem.
4. Record in §12 what was soldered and when. The previous diagnosis was slow to determine the cause because this history was missing (`README.md` §4.9, 2026-10-07 update).

---

## 12. Work log

| Item | Value |
|---|---|
| Work date | 2026-10-13 |
| New board serial/label | |
| Step 2 SWD device ID (CubeProgrammer output) | 0x468, STM32G43x/G44x, Rev X, VTARGET 3.24 V, RDP Level 0 (after ST-LINK upgrade) |
| ST-LINK firmware (before → after upgrade) | SN 0674FF514948787067045114: V2J28M18 → **V2J48M35** (CLI `-sn <SN> -update`, succeeded on the first try right after re-plugging USB) |
| Option bytes (before → after change) | nSWBOOT0 1 → **0**, nBOOT0 1 → 1, RDP 0xAA kept |
| Flashed firmware version (`0x20250226` expected) | 0x20250226 (confirmed via `controller.firmware_version` in RAM) |
| `FIRST_TIME_BOOTUP` of the last build | first boot (=1) flash → normal (=0) flash done. Then demo build (`DEMO_STANDALONE=1`), and finally the open-loop demo build (`recoil_openloop_demo.elf`, `OPENLOOP_NO_ENCODER=1`) flashed |
| Step 7 PC value, 2 reads | After hard reset 0x080034E6 / 0x08003506 (`HAL_GetTick`/`HAL_Delay`, running). However the call stack is `MotorController_init → Encoder_init` — see below |
| ESC CAN connector silkscreen pin order | |
| CANH–CANL resistance: power OFF / ESC running | |
| CAN_TERM (PC14 LOW) polarity judgment | **PC14 LOW = termination OFF, HIGH = ON** (2026-10-13: Bit1 errors and BUS-OFF at LOW, no errors at HIGH. Not a direct resistance measurement). Fixed HIGH in firmware with `CAN_TERMINATION_ENABLED=1` |
| AS5600 encoder connection location (photo filename) | |
| Soldering history (location, time, re-check result) | 2026-10-13: pin header soldered to the ESC CAN pads (user). Immediately afterwards SWD connection 3.24 V, mode IDLE, errors 0 → passed |

### 2026-10-13 progress log (new board)

- **Steps 2–6 passed.** The new board is fine (SWD connection, flash, verify).
- `make.exe` is blocked by the Windows application control policy, so the build was done with `Recoil-Motor-Controller-BESC/demo/build_variant.sh` (calls gcc directly). `FIRST_TIME_BOOTUP` and `DEMO_STANDALONE` were wrapped in `#ifndef` so they can be changed with `-D`. The normal build size is the same as before (text 48,888 B).
- The ST-LINK upgrade works without the GUI: `java -jar STLinkUpgrade.jar -sn <SN> -update`. The first two attempts failed with a USB communication error (Windows 121); running it **right after re-plugging the USB, with no other connection in between**, succeeded.
- Running with `--start` right after flashing caused a HardFault (CFSR 0x1400, MSP 0xFFFFFFD8). Doing a separate `-hardRst` runs normally → flash with `-w ... -v`, then `-c port=SWD -hardRst`.
- **Stuck at Step 7: AS5600 encoder not responding.** `Encoder_init()` **waits forever** until a response comes on I2C (PB7 = SDA, PB8 = SCL, address 0x36). In this state initialization never finishes, so mode = DISABLED, LED not blinking, no CAN response, UART silent. The encoder must be connected to proceed to the next step.
  - Diagnosis method: `demo/demo_status.ps1` (reads RAM over SWD) → mode 0x00, return address on the stack → `Encoder_init`.
- Re-check after the user said the encoder-side wiring had been connected (same day): still waiting in `Encoder_init`. An **I2C bus scan** (`APP_i2cScan`, 0x08–0x77) was added to the demo build; the result was **0 responding devices**, and reading 0x36 gives `HAL_I2C_ERROR_AF` (NACK). PB7·PB8 are HIGH at idle (internal pull-ups), so they are not shorted → need to check encoder power, SDA/SCL pin locations, and SDA↔SCL swapped.
  - Tried probing by writing I2C registers directly with CubeProgrammer `-w32`, but it failed at the post-write verify stage and the writes did not take effect → switched to an in-firmware scan.
- The user then confirmed **there is no encoder** → switched to the open-loop build (`OPENLOOP_NO_ENCODER`); initialization passed (IDLE, errors 0), then open-loop drive succeeded (`MOVE_WITHOUT_CAN.md` §D).
- CAN: initially BUS-OFF (bit errors). After switching to a CANable, four ESC-side causes (CAN pad contact → pin header soldered, a missing wire, CANH/CANL swapped, no termination) and a firmware RX FIFO backlog bug were fixed, giving **PYNQ → CANable → ESC communication and successful open-loop drive**. The PS CAN0 + SN65HVD230 path still does not work (`CAN_SETUP.md` §5).

After filling in the log:

1. Attach this table as an appendix when writing report v3.0 (scenario §8).
2. Proceed from **T1 (bus connection check)** in the scenario document.
   ```
   ip -d -s link show can0            # ERROR-ACTIVE, berr-counter 0/0
   $PY host/recoil_cli.py scan        # devices: [1]
   ```

---

## References

- `README.md` §4 (gotchas), §6 (command collection), §4.9 (diagnosis of the previous board not responding)
- `CAN_SETUP.md` §5 (2026-10-13 diagnosis and resolution)
- `../actuator-vqc-control-report-scenario.md` (P1–P6 prerequisites, T0–T9 tests)
- `pynq-can/README.md` (Pmod JA wiring, host commands)
- Firmware source: `Core/Inc/main.h` (GPIO_CAN_TERM = PC14), `Core/Src/main.c:901` (initially LOW, then HIGH in `APP_init` depending on `CAN_TERMINATION_ENABLED`), `Core/Src/stm32g4xx_hal_msp.c` (FDCAN1 PA11/PB9)
- ST UM2516 (B-G431B-ESC1 user manual) — CAN connector pin order and termination circuit. ⚠ Original not verified; based on summary sources
