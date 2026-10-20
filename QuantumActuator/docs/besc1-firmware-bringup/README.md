# B-G431B-ESC1 Firmware Bring-up Log

**Date**: 2026-09-20
**Target board**: STMicroelectronics B-G431B-ESC1 (MCU: STM32G431CB, 128KB Flash, Cortex-M4 @ 160MHz)
**Project**: Berkeley Humanoid Lite
**Motor**: MAD 5010 110KV (14 pole pairs, Kt=0.1176 N·m/A) + 15:1 cycloidal actuator

---

## 1. Final Result Summary

| Item | Status |
|---|---|
| Firmware source obtained | ✅ `Recoil-Motor-Controller-BESC` |
| STM32CubeIDE installed | ✅ v2.2.0 @ `C:\ST\STM32CubeIDE_2.2.0\` |
| ST-LINK firmware upgrade | ✅ V2J28M18 → **V2J48M35** |
| Recoil firmware build | ✅ 48.7 KB ELF (38% of Flash used) |
| B-G431B-ESC1 flash | ✅ verify OK |
| Option byte change (nSWBOOT0=0) | ✅ main flash boot confirmed |
| Motor profile setting | ✅ `MOTORPROFILE_MAD_5010_110KV` |
| Load-from-Flash flags disabled | ✅ code defaults used |
| Provisioning ritual (`FIRST_TIME_BOOTUP`) | ✅ done |
| CAN path | ✅ (2026-10-13) PYNQ → CANable 2.0 (slcan) → ESC communication and open-loop drive succeeded. ❌ PS CAN0 + SN65HVD230 path does not work (`CAN_SETUP.md` §5) |
| Motor calibration / rotation test | ⚠️ **Open-loop drive done** with the new ESC (2026-10-13). Calibration and closed-loop on hold because there is no encoder (AS5600) |
| **SWD reconnection (on the 2026-10-03 restart)** | ❌ **`Unable to get core ID`**. Cause: a component overheated during soldering (user report, 2026-10-07) → board replaced (✅ new board on 2026-10-13, `BOARD_REPLACEMENT.md`) |

> ⚠️ **Update (2026-10-03)**: The ✅ items above reflect the state at the end of the 2026-09-20 session. After the project restarted, **SWD/JTAG were completely unresponsive**, and the board at the time (the failed board) could not be accessed. Read §4.8 / §4.9 below first.

> 🛠 **2026-10-07 — new board purchased**: The replacement procedure is in **`BOARD_REPLACEMENT.md`**. It bundles the commands from §4 and §6 of this document in order, and adds pre-soldering checks, CAN wiring, termination measurement, soldering rules, and a work log sheet.

> 🔎 **Retest (2026-10-07) (failed board, ST-LINK SN 066FFF565155807167082134, FW V2J48M35)**: VTARGET 3.23 V, normal. SWD Hotplug / Normal 24 kHz / Under-reset+HW reset 100 kHz and JTAG 100 kHz all gave `Unable to get core ID` (JTAG gave `DEV_UNKNOWN_MCU_TARGET`). Same symptom as 2026-10-03 — this board can be neither flashed nor driven. However, if the board LED blinks, the MCU core is running the firmware flashed in September and only the debug port is dead, so it may still respond over CAN.
> - User confirmation the same day: **LED blinking** → judged that the MCU core is running firmware and only the debug port has failed. PYNQ `recoil_cli.py scan` → no response, can0 BUS-OFF (the expected symptom with the SN65HVD230 not yet wired). The firmware has no UART command receive path (`HAL_UART_Receive` is not used) → **CAN is the only command channel**. Retest needed after wiring the transceiver.

> 🔥 **Update (2026-10-07) — cause of failure confirmed**: According to the user's report, **a component overheated while soldering on the board, and the board failed** (component and timing unknown).
> - The SWD/JTAG unresponsiveness in §4.9 is judged to be caused by this damage. Of the "ESD / solder joint / USB power" hypotheses left at the time, ESD is rejected. Solder-related damage is in the same family as the actual cause.
> - The diagnosis at the time only confirmed "no electrical events" and **did not ask about rework (soldering) history.** From now on, hardware diagnosis starts by checking recent physical work history.
> - **Action**: replace the board. The new board goes through the §4 and §6 procedures of this document from the beginning. Do not solder directly to the ESC; wire it with connectors or crimp terminals. If soldering is unavoidable, use a temperature-controlled iron for no more than 3 seconds per joint, and check the 3V3 rail and the SWD connection right after the work.

> 📌 **Update (2026-10-06)**: During the 2026-10-04~06 development period, the ESC/ST-LINK was also not connected to the PC (no VID 0483 in the USB device list). A board replacement or recovery was **not logged.** The "recovered by board replacement" in the v1.0 report was an assumption and was corrected in the v2.0 report (`../actuator-vqc-control-report.md` §5.7). In the meantime the host side (PYNQ-Z2 CAN, 1 kHz controller, VQC FPGA core) has been completed, so **hardware testing can start as soon as the ESC is recovered.** The order is as follows.
> 1. Re-flash the ESC (§6 of this document).
> 2. Wire the transceiver.
> 3. Run `recoil_cli.py scan` → `info` → `calibrate`.
> 4. Start with `run_controller.py --policy pd --amp 0.05`.
>
> The detailed procedure, predicted values, and pass/fail criteria are in `../actuator-vqc-control-report-scenario.md`. In particular, read §2 (gear ratio −15 and unit conversion) and T3 (with `LOAD_CALIBRATION_FROM_FLASH=0`, calibration is lost on reboot) first.

---

## 2. Understanding the Project Structure

Berkeley Humanoid Lite is split into 3 repositories:

```
HybridRobotics/Berkeley-Humanoid-Lite            (berkeley-humanoid-lite)
  ├─ IsaacLab environment, RL training, simulation
  └─ berkeley_humanoid_lite_lowlevel/            (submodule, empty folder)
        │
        ▼ (the actual code is here)
HybridRobotics/Berkeley-Humanoid-Lite-Lowlevel   (host-side, Linux)
  ├─ CAN 1Mbps communication (python-can + custom Recoil protocol)
  ├─ csrc/motor_controller.{c,h}                 (host-side controller)
  └─ scripts/motor/{ping,calibrate_electrical_offset,move_actuator}.py
        │
        ▼ (CAN 1Mbps)
T-K-233/Recoil-Motor-Controller-BESC             (Recoil-Motor-Controller-BESC)
  └─ STM32G431CB on-board firmware (FOC + FDCAN + I2C encoder)
```

- **Author**: Yufeng Chi (T-K-233) — first author of the Berkeley Humanoid Lite paper
- **Firmware version**: `0x20250226`
- **Protocol**: CANopen-like PDO/SDO, DEVICE_CAN_ID = 1..63

---

## 3. Hardware Details (B-G431B-ESC1)

### 3.1 Interfaces exposed over USB

A single USB (VID_0483) exposes three functions simultaneously:

| Interface | PID | Purpose |
|---|---|---|
| MI_00 | 374B | ST-LINK Debug (SWD) |
| MI_01 | 374B | USB Mass Storage (MBED drag-and-drop) |
| MI_02 | 374B | Virtual COM Port → USART2 (target UART) |
| — | 3748 | ST-LINK bootloader mode (exposed only during firmware upgrade) |

Check on Windows:
```powershell
Get-PnpDevice | Where-Object { $_.InstanceId -match 'VID_0483' } | Format-Table Status, FriendlyName
```

### 3.2 Physical connection

```
Linux/Windows PC
   │ USB Micro-B
   ▼
┌───────────────────────────────────────────┐
│  B-G431B-ESC1                             │
│  ┌──────────────┐  internal SWD wiring    │
│  │ ST-LINK/V2-1 │─────────────┐           │
│  │ (on-board)   │             │           │
│  └──────────────┘             ▼           │
│                     ┌──────────┐          │
│                     │STM32G431 │          │
│                     │   CB     │          │
│                     └──────────┘          │
└──┬────────────────────────────────────────┘
   │
   └─ XT30: 14–55V motor bus (separate bench PSU, current-limited)
```

**Important**: USB only powers the MCU at 3V3. The actual motor phases need the XT30 bus voltage. For flashing, USB alone is enough.

---

## 4. Struggles and Fixes (key gotchas)

### 4.1 ST-LINK firmware V2J28M18 vs STM32CubeProgrammer 2.23 compatibility

**Symptom**: `DEV_USB_COMM_ERR` or `Unable to get core ID` with `-c port=SWD`, while the target voltage is normal.

**Cause**: The factory ST-LINK/V2-1 FW (V2J28) does not match CubeProgrammer 2.23.

**Fix**: Run STLinkUpgrade.jar:
```powershell
$java = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.jre.win64_3.4.300.202604201452\jre\bin\javaw.exe'
$jar  = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.stlink-gdb-server.win32_2.2.500.202604010938\tools\bin\STLinkUpgrade.jar'
Start-Process -FilePath $java -ArgumentList "-jar","`"$jar`""
```

In the GUI: **"Open in update mode"** → **"Upgrade"** → after it finishes you **must close the window**. If the Java process stays alive, it blocks subsequent CLI communication.

### 4.2 BOOT0 pin latching (does not boot from main flash)

**Symptom**: Firmware was flashed, but after a hard reset the PC is at `0x1FFF4B14` (system bootloader region).

**Cause**: The BOOT0 pin (PB8) of the B-G431B-ESC1 is latched HIGH on hard reset. Recoil's `APP_initFlashOption()` writes OPTR but exits without the `OBL_LAUNCH` bit, so the option byte change is not applied.

**Fix**: Change the option bytes directly with STM32CubeProgrammer
```powershell
STM32_Programmer_CLI -c port=SWD -ob nSWBOOT0=0 nBOOT0=1
```

- `nSWBOOT0=0` → decided by the option bit instead of the BOOT0 pin
- `nBOOT0=1` → boot from main flash

### 4.3 Zero-struct save bug in `FIRST_TIME_BOOTUP` provisioning

**Symptom**: With `LOAD_*_FROM_FLASH=1`, HardFault after boot (SCB→CFSR = `0x1400`: STKERR + IMPRECISERR).

**Cause**: `FIRST_TIME_BOOTUP=1` calls `MotorController_storeConfig(&controller)` **before** `MotorController_init()`. At that point `controller` is still in its .bss zero-init state → all zeros are saved to the Flash config page (0x0801F800). On the next boot, `loadConfig` reads these zeros, giving `motor.phase_order=0`, `encoder.cpr=0`, etc., and `MotorController_reset()` hits NaN/divide-by-zero → HardFault.

**Fix**: Set all 3 flags to 0 (`motor_controller_conf.h`)
```c
#define LOAD_ID_FROM_FLASH              0
#define LOAD_CONFIG_FROM_FLASH          0
#define LOAD_CALIBRATION_FROM_FLASH     0
```
→ On init, only the code defaults (`MAD_5010_110KV` in `motor_profiles.h`) are used; Flash is ignored.

### 4.4 gcc 14.3 build error

**Symptom**: `sprintf` implicit function declaration → compilation fails.

**Cause**: Between gcc 12→14, implicit declaration was promoted from a warning to a hard error.

**Fix**: Add `#include <stdio.h>` at the top of `motor_controller.c`.

### 4.5 Hardcoded absolute paths in the CubeIDE project

**Symptom**: Running `make` gives `objects.list` missing + the linker script path is `C:\Users\TK\Desktop\...` (the original author's local path).

**Fix**:
- Edit `Release/makefile`: `-T"C:\Users\TK\..."` → `-T"../STM32G431CBUX_FLASH.ld"`
- Create `objects.list` manually (extracted with PowerShell from the `OBJS +=` blocks in subdir.mk)

### 4.6 STM32_Programmer_CLI's default connect halts + soft-resets the CPU

**Symptom**: Reading the PC after several halts always gives `Reset_Handler` (initial address `0x0800XXXX`).

**Cause**: The default `-c port=SWD ...` mode issues a software reset on connect. Every time, you are observing a state that was just reset.

**Fix**: Use `mode=Hotplug` when you need a live snapshot
```powershell
STM32_Programmer_CLI -c port=SWD mode=Hotplug -r32 0x20000210 32
STM32_Programmer_CLI -c port=SWD mode=Hotplug --coreReg PC
```

### 4.7 STLINK bad state → re-plug USB

`DEV_USB_COMM_ERR` occurred repeatedly during the session, especially in these situations:
- When the STLinkUpgrade Java process is still alive
- When Hotplug-mode reads are repeated many times in a short period
- Right after a failed connect attempt

**Fix**: Unplug and re-plug the USB (wait 5 seconds before re-inserting). If needed, kill lingering processes:
```powershell
Get-Process javaw, java, STM32_Programmer_CLI -EA SilentlyContinue | Stop-Process -Force
```

### 4.8 USART2 is silent during normal operation — UART silence is not a liveness signal

**Beware of misdiagnosis**: Nothing coming out of COM4 (VCP) does not mean the MCU is dead.

The firmware has 6 `HAL_UART_Transmit(&huart2, ...)` call sites in total, and all of them execute only in special situations:

| Location (`Core/Src/motor_controller.c`) | Execution condition |
|---|---|
| `:100` | **Only on init failure** (`status != HAL_OK` → infinite error loop with a 1-second period) |
| `:446` | `MotorController_calibrate()` — wait loop while bus voltage < 9V |
| `:480`, `:533`, `:548`, `:578`, `:585` | All inside `MotorController_calibrate()` |

`MotorController_calibrate()` runs **only when `MODE_CALIBRATION` (0x05) is entered via a CAN command** (see §9). Therefore:

> **Firmware that booted normally and is waiting in `MODE_IDLE` does not send a single byte over USART2.**

The UART transmit at `app.c:166` is also commented out, so there is not even a boot banner.

**In other words, COM4 silence is consistent with all three of the following states**, so it has no diagnostic value:
1. Normal operation (`MODE_IDLE`, waiting for CAN commands) ← **the most common case**
2. MCU completely stopped / not started
3. Firmware built with `FIRST_TIME_BOOTUP=1` (the `while(1){}` infinite loop at `app.c:111`)

Check liveness **only with an SWD hotplug snapshot** (§4.6, §8) or a **CAN ping** (§10). A baud sweep (115200~2000000) is a waste of time — in the 2026-10-03 session all 6 rates were confirmed to give 0 bytes.

### 4.9 `Unable to get core ID` debugging checklist (evidence ruling out software causes)

`Unable to get core ID` is an **SWD-DP level** failure unrelated to core state. Whatever state the firmware is in (hard fault, blank flash, GPIO reassignment, system bootloader), the DP must respond, so **this symptom cannot be explained by a firmware problem.**

#### OPTR value decode — RDP Level 2 hypothesis permanently ruled out

`FLASH->OPTR = 0xFBEFF8AAU` written by `app.c:85`:

| Field | Bits | Value | Meaning |
|---|---|---|---|
| `RDP` | [7:0] | `0xAA` | **Level 0 — debug allowed** ✅ |
| `BOR_LEV` | [10:8] | `0b000` | BOR level 1 |
| `nRST_STOP` / `nRST_STDBY` / `nRST_SHDW` | 12/13/14 | `1`/`1`/`1` | no reset |
| `nBOOT1` | 24 | `1` | — |
| `nSWBOOT0` | 27 | `1` | BOOT0 decided by the **PB8 pin** ⚠️ (conflicts with §4.2) |
| `nBOOT0` | 28 | `1` | — |
| `NRST_MODE` | [30:29] | `0b11` | standard reset input/output ✅ |

**Neither the firmware nor §4.2's `-ob nSWBOOT0=0 nBOOT0=1` touches RDP.** Therefore the hypothesis that "debug was permanently blocked by writing the option bytes incorrectly" can be ruled out.

#### Forcing hardware BOOT0 entry is not effective on this board

Even if the system bootloader is entered, **there is no communication path**:
- BOOT0 = **PB8** (§4.2)
- STM32G431 bootloader USART1 = PA9/PA10 → **occupied by PWM high-side** on this board
- USB DFU = PA11/PA12 → **occupied by PWM low-side**, not brought out to a connector

#### Symptom log (2026-10-03 session) — cause confirmed on 2026-10-07: a component overheated during soldering

A board that had been in the normal operating state logged in §8 was completely unresponsive on SWD/JTAG after the restart. Everything below was ruled out, but the cause was not identified:

| Attempt | Result |
|---|---|
| `mode=HOTPLUG` / `mode=UR` / `reset=HWrst` | All `Unable to get core ID` |
| `freq=480` / `100` / `15` / `5` (kHz) | All failed |
| `port=JTAG` | `DEV_UNKNOWN_MCU_TARGET` |
| §4.7 USB re-plug | 3 interfaces re-enumerated normally, SWD still fails |
| §4.7 kill lingering processes | No such processes |
| baud sweep (§4.8) | 0 bytes on COM4 for all 6 rates |
| §4.1/§6.6 re-run STLinkUpgrade | **"Upgrade successful" (V2J48M35 rewritten) — SWD still fails** |

#### ST-LINK side proven healthy

STLinkUpgrade communicated with the ST-LINK over USB and **successfully rewrote its firmware** (`ST-Link ID: 066FFF565155807167082134`, `Type: STM32 Debug+Mass storage+VCP`), and VTARGET sensing also works (3.21~3.23V). That is, **the on-board ST-LINK (STM32F103) itself is completely healthy**.

→ The fault location is confirmed to be **between the ST-LINK ↔ STM32G431 or on the G431 side**. Remaining candidates:
- MCU VDD not reached (3V3 regulator/buck damaged) — `VTARGET` is just the rail the ST-LINK senses and **does not prove it reaches the MCU VDD pins**
- **NRST line stuck LOW** — if NRST stays asserted, the debug power domain is also held in reset and the DPIDR read fails, a symptom that matches `Unable to get core ID` exactly
- STM32G431 itself damaged

#### Power-stage incident ruled out (confirmed 2026-10-03)

User confirmation: **power was never applied to XT30, and a motor was never connected to the 3-phase terminals.** This board was handled **on USB power only** from the very beginning. Therefore power-stage incident hypotheses such as overvoltage, reverse polarity, or FET shorts are ruled out.

#### Logged command history is also all benign

None of the commands left in §6 can block debug:
- `-ob nSWBOOT0=0 nBOOT0=1` → RDP unchanged (read-modify-write)
- `--hardRst` → just an NRST pulse
- `-ob displ`, `-r32`, `--coreReg` → read-only
- **No record of `-ob RDP=...` / `--readunprotect` / `--obl`-type commands being run**

#### Summary: both software and power stage ruled out

Normal operation on 2026-09-20 (§8) → stored for about 2 weeks → DP unresponsive at restart on 2026-10-03. No electrical events in between. What remains is roughly **ESD during storage/handling**, a **bad solder joint**, or **insufficient USB power supply margin** (when going through a hub). In the next session, **start with measurements** — CLI retries have already been exhausted.

> **Addendum (2026-10-07)**: The actual cause was **a component overheated during soldering** (user report, see the top of this document). The "no electrical events in between" above was the result of checking only power application and motor connection; rework (soldering) history was not on the checklist.

Side clues: `Board : --` (board name blank), MSD volume label `UNDEFINED`, `E:\FAIL.TXT` = `The interface firmware FAILED to reset/halt the target MCU`. The ST-LINK has lost the board identifier — suspected to be related to the STLinkUpgrade run in §4.1.

**(Failed board historical note) Next-attempt order at the time**: (1) re-run STLinkUpgrade per §4.1 to reset the ST-LINK state → (2) measure MCU VDD with a multimeter. `VTARGET 3.22V` is the ST-LINK's rail sensing and **does not prove it reaches the MCU VDD pins.**

---

## 5. List of Locally Modified Files (vs. upstream)

Files modified locally in the Recoil repository:

### 5.1 `Core/Inc/motor_controller_conf.h`
```diff
-#define LOAD_ID_FROM_FLASH              1
+#define LOAD_ID_FROM_FLASH              0
-#define LOAD_CONFIG_FROM_FLASH          1
+#define LOAD_CONFIG_FROM_FLASH          0
-#define LOAD_CALIBRATION_FROM_FLASH     1
+#define LOAD_CALIBRATION_FROM_FLASH     0
-#define MOTORPROFILE_MAD_M6C12_150KV
-//#define MOTORPROFILE_MAD_5010_110KV
+//#define MOTORPROFILE_MAD_M6C12_150KV
+#define MOTORPROFILE_MAD_5010_110KV
+#ifndef DEMO_STANDALONE
+#define DEMO_STANDALONE                 0    (2026-10-07, default 0)
+#endif
```

On 2026-10-07 an `#if DEMO_STANDALONE` block (button-triggered calibration and sine back-and-forth motion) was also added to `Core/Src/app.c`. It is not included in the default build. Usage is in `MOVE_WITHOUT_CAN.md`.

### 5.2 `Core/Src/motor_controller.c`
```diff
+#include <stdio.h>
 #include "motor_controller.h"
```

### 5.3 `Release/makefile`
```diff
-... -T"C:\Users\TK\Desktop\Recoil-Motor-Controller\firmware\Recoil-Motor-Controller-B-G431B-ESC1\STM32G431CBUX_FLASH.ld" ...
+... -T"../STM32G431CBUX_FLASH.ld" ...
```

### 5.4 `Release/objects.list` (newly created)
41 object file paths (Core/Src/*.o, Core/Startup/startup*.o, Drivers/STM32G4xx_HAL_Driver/Src/*.o).

---

## 6. Reusable Command Collection

### 6.1 Environment variables (before every build/flash)

```powershell
$env:PATH = "C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.14.3.rel1.win32_1.0.100.202602081740\tools\bin;" +
            "C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.make.win32_2.2.200.202604021615\tools\bin;" +
            $env:PATH

$PROG = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.win32_2.2.500.202603051304\tools\bin\STM32_Programmer_CLI.exe'
$ELF  = 'Recoil-Motor-Controller-BESC/Recoil-Motor-Controller-B-G431B-ESC1/Release/Recoil-Motor-Controller-B-G431B-ESC1.elf'
```

### 6.2 Build

```powershell
Set-Location 'Recoil-Motor-Controller-BESC/Recoil-Motor-Controller-B-G431B-ESC1/Release'
make clean
make -j8 all
```

### 6.3 Flash + verify + auto-run

```powershell
& $PROG -c port=SWD -w $ELF -v --hardRst --start
```

### 6.4 Live diagnostics (CPU keeps running)

```powershell
# first 32 bytes of the controller struct
& $PROG -c port=SWD mode=Hotplug -r32 0x20000210 32

# Cortex-M4 core registers (including PC)
& $PROG -c port=SWD mode=Hotplug --coreReg

# a specific register only
& $PROG -c port=SWD mode=Hotplug --coreReg PC

# Fault status registers
& $PROG -c port=SWD mode=Hotplug -r32 0xE000ED28 16    # CFSR + HFSR + DFSR + MMFAR
```

### 6.5 Option byte management

```powershell
# show all
& $PROG -c port=SWD -ob displ

# set specific values
& $PROG -c port=SWD -ob nSWBOOT0=0 nBOOT0=1
```

### 6.6 ST-LINK firmware upgrade

```powershell
$java = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.jre.win64_3.4.300.202604201452\jre\bin\javaw.exe'
$jar  = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.stlink-gdb-server.win32_2.2.500.202604010938\tools\bin\STLinkUpgrade.jar'
Start-Process -FilePath $java -ArgumentList "-jar","`"$jar`""
# In the GUI: Open in update mode → Upgrade → close the window
```

### 6.7 Finding symbol locations (ELF parsing)

```powershell
$env:PATH = "C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.14.3.rel1.win32_1.0.100.202602081740\tools\bin;$env:PATH"

# controller symbol address
arm-none-eabi-nm --print-size $ELF | Select-String '\bcontroller\b'

# function names corresponding to addresses
arm-none-eabi-nm --numeric-sort $ELF | Select-String '^0800(34|35)'
```

---

## 7. Current Firmware Configuration (final flashed version)

> **New board (2026-10-13)**: In addition to the settings below, the board runs `recoil_openloop_demo.elf`, which includes the local options `OPENLOOP_NO_ENCODER=1` (no encoder), `DEMO_STANDALONE=1`, `CAN_TERMINATION_ENABLED=1` (PC14 HIGH) and the RX FIFO drain fix. It is built with `Recoil-Motor-Controller-BESC/demo/build_variant.sh` (calls gcc directly because make is blocked). The table below reflects the 2026-09-20 standard build.

```
Firmware Version    : 0x20250226
Motor Profile       : MAD_5010_110KV (14PP, Kt=0.1176 N·m/A, R=0.6193Ω, L=85µH)
Motor Calibration I : 3A
Nominal Bus Voltage : 12V
Commutation Freq    : 10 kHz
Position Update Freq: 2 kHz
Encoder Precision   : 12-bit (4096 CPR)
Encoder Direction   : +1
Phase Order         : +1
DEVICE_CAN_ID       : 1
CAN Bitrate         : 1 Mbps (FDCAN)
UART (VCP)          : USART2 @ 1,000,000 baud
Safety Watchdog     : Enabled (1000 ms)
LOAD_ID/CONFIG/CAL  : 0 / 0 / 0 (Flash ignored, code defaults used)
FIRST_TIME_BOOTUP   : 0
```

---

## 8. Confirmed Live State

> ⚠️ **This section is a snapshot as of 2026-09-20.** After the 2026-10-03 restart, SWD was unresponsive, so the values below could not be re-verified (§4.9). Do not use this log as evidence that "the current board is healthy" — however, since it is **evidence that the board once worked completely normally**, it is grounds to suspect the hardware/ST-LINK side rather than the firmware/option byte side.

Firmware execution confirmed (hotplug SWD snapshot):
- **PC**: cycling between `0x080034E4`~`0x0800350E` → `HAL_Delay` / `HAL_GetTick` loop (normal operation)
- **CFSR/HFSR**: 0 / 0 (no fault)
- **SP**: `0x20007ED8` (near the top of RAM, normal stack)
- **IPSR**: 0 (thread mode, not an exception handler)
- **controller.device_id**: 1
- **controller.firmware_version**: `0x20250226`
- **controller.watchdog_timeout**: 1000 ms

Whether the final mode value is `0x00 (MODE_DISABLED)` or `0x01 (MODE_IDLE)` needs to be re-checked over CAN (can be determined by whether the first CAN ping gets a response).

---

## 9. "If I plug in only USB and power XT30, will the motor spin?" → **No**

### Reason

Recoil is a **CAN-command-based** motor controller. The default state after boot is `MODE_IDLE`, and in this state **3-phase PWM is disabled**. Even if 24V is applied to XT30, the phase output = 0V → the motor does not rotate.

### Mode transitions needed to spin the motor

| Mode | Trigger | Behavior |
|---|---|---|
| `MODE_DISABLED` (0x00) | initial/error | PWM fully off |
| `MODE_IDLE` (0x01) | after successful boot | waiting, PWM off |
| `MODE_CALIBRATION` (0x05) | CAN command | short step rotation (learns encoder flux offset) |
| `MODE_TORQUE`/`VELOCITY`/`POSITION` | CAN command | **actual rotation** |

Mode transitions are possible only via CAN SDO/PDO frames. Therefore a CAN adapter is mandatory.

### Design philosophy of this firmware

- Since it is a joint actuator for a robotic humanoid, it is a **system in which the host always issues commands**
- No stand-alone features such as automatic rotation (power-on-auto-spin) or potentiometer control
- Safety watchdog (1000ms): if commands stop, it automatically decays into damping mode

---

## 10. Next Steps (after obtaining a CAN adapter)

> As of 2026-10-13, the working CAN path is **PYNQ USB → CANable 2.0 (slcan)**, and the PYNQ-Z2 PS CAN + SN65HVD230 path does not work (`CAN_SETUP.md` §5). New board preparation follows `BOARD_REPLACEMENT.md`, and hardware testing follows `../actuator-vqc-control-report-scenario.md`. Below is the historical note of the original plan.

### 10.1 Hardware preparation

1. **Buy a CAN adapter**
   - Cheap option: CANable v2 (~$30) — supported on both Windows/Linux with the candlelight/gs_usb driver
   - Reliable: PEAK PCAN-USB (~$300)
   - Middle: Innomaker USB2CAN
2. **Motor bus PSU** (14–55V, current-limited)
   - Lab bench PSU recommended (start with 24V, 2A limit)
   - **Do not connect a battery directly**
3. **Leave the actuator output shaft free to rotate** (no load connected anywhere)

### 10.2 Software (Python)

```bash
# prepare python-can + Recoil host-side lib
pip install python-can pyserial
git clone https://github.com/HybridRobotics/Berkeley-Humanoid-Lite-Lowlevel.git
cd Berkeley-Humanoid-Lite-Lowlevel
pip install -e .
```

### 10.3 Bring-up order

1. **Ping test** (possible even with motor bus power OFF)
   ```bash
   python scripts/motor/ping.py --id 1
   # expected output: "Motor is online"
   ```
2. **Apply motor bus power** (24V, 2A limit)
3. **Electrical offset calibration** (automatic encoder flux offset detection)
   ```bash
   python scripts/motor/calibrate_electrical_offset.py --id 1
   # the motor briefly step-rotates during calibration — normal
   ```
4. **Open-loop low-speed rotation** (apply phase voltage directly with Vabc override)
5. **Closed-loop torque/velocity/position control**

### 10.4 Safety preparation

- **E-stop**: keep the PSU switch within reach
- **The first start must begin with a low current limit** (increase in steps 2A → 5A → 10A)
- Avoid abrupt commands, taking into account **the backlash and inertia of the cycloidal reducer**
- If a problem occurs, immediately PSU OFF → re-verify the firmware over USB only

---

## 11. Reference Links

- **Firmware (actual flash target)**: https://github.com/T-K-233/Recoil-Motor-Controller-BESC
- **Host-side code**: https://github.com/HybridRobotics/Berkeley-Humanoid-Lite-Lowlevel
- **Main project**: https://github.com/HybridRobotics/Berkeley-Humanoid-Lite
- **Paper (arXiv)**: https://arxiv.org/abs/2504.17249
- **B-G431B-ESC1 official page**: https://www.st.com/en/evaluation-tools/b-g431b-esc1.html
- **STM32G431CB datasheet/RM**: https://www.st.com/en/microcontrollers-microprocessors/stm32g431cb.html
- **STM32CubeIDE download**: https://www.st.com/en/development-tools/stm32cubeide.html

---

## 12. Troubleshooting Checklist

When something does not work in a later session, check in order:

- [ ] Is the USB definitely recognized? `Get-PnpDevice | ? { $_.InstanceId -match 'VID_0483' }`
- [ ] Is the ST-Link Debug status `OK`? (if `Error`, reinstall the ST-LINK driver from the CubeIDE installer)
- [ ] Is the ST-LINK FW V2J45+? `STM32_Programmer_CLI -l st-link`
- [ ] Is no STLinkUpgrade.jar Java process left in the background? `Get-Process javaw`
- [ ] When checking live with `mode=Hotplug`, is the PC within the Flash range (0x0800xxxx)? (if `0x1FFFxxxx`, it is the system bootloader — re-check the option bytes)
- [ ] Are the option bytes `nSWBOOT0=0 nBOOT0=1`? `STM32_Programmer_CLI -c port=SWD -ob displ`
- [ ] Is the firmware version field `0x20250226`? `-r32 0x20000214 4`
- [ ] Is SCB→CFSR (`0xE000ED28`) 0? If not 0, it is in a fault state

**When COM4 (VCP) is silent** → that is normal. Do not use it for diagnosis (§4.8). Firmware waiting in `MODE_IDLE` sends nothing over UART. Check liveness only with SWD hotplug or CAN ping.

**When `Unable to get core ID` appears** → the following causes have already been ruled out, so do not repeat them (§4.9):
- [x] ~~baud mismatch~~ → a symptom unrelated to UART
- [x] ~~RDP Level 2~~ → `RDP=0xAA` in `OPTR=0xFBEFF8AA` = Level 0
- [x] ~~NRST changed to GPIO~~ → `NRST_MODE=0b11` standard
- [x] ~~SWD clock too fast~~ → fails even when lowered to 5 kHz
- [x] ~~firmware reassigns SWD pins~~ → the DP is independent of core state
- [ ] (failed board, discarded) **Not yet tried**: re-run STLinkUpgrade (§6.6) → measure MCU VDD with a multimeter
