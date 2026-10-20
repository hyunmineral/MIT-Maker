# Local changes to the Recoil firmware

Upstream: https://github.com/T-K-233/Recoil-Motor-Controller-BESC (commit 3571ab6, MIT).
`firmware_local_changes.patch` is the source diff against that commit. New behaviour is behind compile-time
options whose defaults keep upstream behaviour, except where marked "always on".

| Change | Where | Option |
|---|---|---|
| Motor profile MAD 5010 110KV; `LOAD_*_FROM_FLASH = 0` (avoids the zero-struct store bug) | `Core/Inc/motor_controller_conf.h` | — |
| `#include <stdio.h>` for gcc 14 | `Core/Src/motor_controller.c` | — |
| RX FIFO drained in the CAN callback (fixes a 2-frame reply lag after bus errors) | `Core/Src/app.c` | always on |
| 120 Ω CAN terminator on at boot (PC14 high) | `Core/Src/app.c` | `CAN_TERMINATION_ENABLED` (default 1) |
| Open-loop drive without encoder: `MODE_VALPHABETA_OVERRIDE`, RPDO3 = [angle, voltage] → TPDO3 = [applied angle, phase current]; encoder-dependent modes refused | `Core/Src/encoder.c`, `Core/Src/motor_controller.c`, `Core/Inc/motor_controller.h` | `OPENLOOP_NO_ENCODER` (default 0) |
| Standalone demo: user button (or RAM `demo_remote_press` over SWD) → calibration + sine, or open-loop sine; I2C bus scan at boot | `Core/Src/app.c` | `DEMO_STANDALONE` (default 0) |
| `FIRST_TIME_BOOTUP`, `DEMO_STANDALONE`, `OPENLOOP_NO_ENCODER`, `CAN_TERMINATION_ENABLED` overridable with `-D` | `Core/Inc/motor_controller_conf.h` | — |

`demo/build_variant.sh` builds any variant from source (no STM32CubeIDE project build needed); the flash image is
byte-identical to the IDE Release build. Prebuilt ELFs in `demo/`: `recoil_normal.elf` (closed loop, needs an
AS5600), `recoil_first_boot.elf`, `recoil_demo_standalone.elf`, `recoil_openloop.elf` (CAN), `recoil_openloop_demo.elf`
(CAN + button). `demo/demo_status.ps1` reads the running state over SWD; `demo/sim_demo.py` checks the demo gains
on the joint model. The STM32CubeIDE project files are kept, so the project still opens in the IDE.
