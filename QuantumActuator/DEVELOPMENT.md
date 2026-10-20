# Development guide

How to set up the tools, build every component, put it on the hardware and run it.

## 1. Tools

| Tool | Version used | For |
|---|---|---|
| Python | 3.12 | training, tools, tests (`pip install numpy torch matplotlib python-docx python-pptx playwright imageio-ffmpeg`) |
| Vivado / Vitis HLS | 2024.1 | bitstreams, HLS core (2026.1 needs a license file even for the free tier) |
| STM32CubeIDE | 2.2.0 | arm-none-eabi-gcc 14.3, STM32CubeProgrammer CLI 2.23, STLinkUpgrade |
| Google Chrome | any recent | headless rendering of SVG figures, website tests (Playwright `channel="chrome"`) |
| PYNQ-Z2 image | v3.1.1 | board OS (PYNQ 3.1, kernel 6.6) |

On the original development PC `make.exe` was blocked by Windows Application Control, which is why the firmware is
built by a plain bash + gcc script (`Recoil-Motor-Controller-BESC/demo/build_variant.sh`).

## 2. PYNQ-Z2 board

1. Write the PYNQ v3.1.1 image to the SD card (`hardware/pynq_sd_card_scripts/write_sd.ps1` checks disk serial,
   size and bus before writing; edit the expected values first). Boot jumper JP4 = SD.
2. Network: direct Ethernet, PC `192.168.2.1/24`, board `192.168.2.99` (user `xilinx`, PYNQ default password).
   The board has no RTC and no internet; set the date from the PC after boot.
3. Copy the code: `pynq-can/{host,vqc,hls}` → `~/vqc_ctrl/`, and `pynq-can/vivado/out/vqc_can0.{bit,hwh}` +
   `xvqc_top_hw.h` → `~/vqc_ctrl/overlay/`; `ln -sf vqc_can0.bit ~/vqc_ctrl/overlay/active.bit`;
   `make -C ~/vqc_ctrl/vqc libvqc.so`.
4. CAN0 at boot: copy `can0-enable.dtbo` and `load_overlay.py` to `/usr/local/lib/firmware/`, `can0-overlay.service`
   to `/etc/systemd/system/`, then `sudo systemctl enable --now can0-overlay`. The service must run after
   `bootpy.service` (PYNQ's `boot.py` loads `base.bit` and would overwrite the PL). Check with `ip -d link show can0`.
5. `$PY` below is `/usr/local/share/pynq-venv/bin/python3`.

## 3. Building

| Component | Command |
|---|---|
| Policy training | `cd pynq-can/vqc && python train.py --out vqc_params.json` (≈ 35 min CPU); MLP baselines `--model mlp --hidden 8`; reference vectors `python export_vectors.py vqc_params.json` |
| HLS core | `cd pynq-can/hls && vitis_hls -f run_hls.tcl && vitis_hls -f cosim.tcl` |
| Bitstreams | `cd pynq-can/vivado && vivado -mode batch -nojournal -source build_can0_overlay.tcl` (`-tclargs can_only` for the CAN-only design); prebuilt results in `vivado/out/` |
| C kernel / PL driver (board) | `make -C ~/vqc_ctrl/vqc libvqc.so bench bench_pl` |
| Firmware | `bash Recoil-Motor-Controller-BESC/demo/build_variant.sh <name> [-D...]` — see the variants in the script header. Compiles everything from source; the flash image is identical to the STM32CubeIDE Release build |
| Figures / docx / pptx | `python docs/tools/make_figures.py`, `update_concept_figures.py`, `build_docx.py`, `build_pptx.py` |
| Website data | `python website/tools/export_data.py` (policies, results), `python website/tools/export_hw_log.py` (hardware log) |

Firmware compile-time options (all in `Core/Inc/motor_controller_conf.h`, overridable with `-D`):
`FIRST_TIME_BOOTUP`, `DEMO_STANDALONE`, `OPENLOOP_NO_ENCODER`, `CAN_TERMINATION_ENABLED` (default 1).
Upstream differences are listed in `Recoil-Motor-Controller-BESC/LOCAL_CHANGES.md`.

## 4. Motor controller (B-G431B-ESC1)

```powershell
$PROG = '...\STM32_Programmer_CLI.exe'
& $PROG -c port=SWD mode=Hotplug                          # connect without resetting the CPU
& $PROG -c port=SWD -ob nSWBOOT0=0 nBOOT0=1               # once per new board
& $PROG -c port=SWD -w recoil_openloop_demo.elf -v        # flash + verify
& $PROG -c port=SWD -hardRst                              # then reset (do not use --start)
```

- New board: upgrade the factory ST-LINK first (`java -jar STLinkUpgrade.jar -sn <SN> -update`, right after
  re-plugging USB), then `recoil_first_boot.elf` → `recoil_normal.elf` (two-stage first flash).
  Full procedure: `docs/besc1-firmware-bringup/BOARD_REPLACEMENT.md`.
- `recoil_normal.elf` waits in `Encoder_init` until an AS5600 answers on I2C1 (SDA = PB7 = hall connector H2,
  SCL = PB8 = H3, address 0x36). Without an encoder use the open-loop builds.
- Live state over SWD: `powershell -File Recoil-Motor-Controller-BESC/demo/demo_status.ps1 -Elf <flashed elf>`.
  The demo builds can be started/stopped remotely by writing 1 to the RAM variable `demo_remote_press`.
- CAN connector: CANH/CANL/GND only (never the 5 V pin to a 3.3 V transceiver); the ESC terminator is on when
  PC14 is high (`CAN_TERMINATION_ENABLED=1`).

## 5. Running

| What | Where | Command |
|---|---|---|
| Unit tests (protocol, emulator) | PC or board | `cd pynq-can/host && python -m unittest test_recoil` |
| CAN self test (controller loopback) | board | `sudo $PY pynq-can/can_loopback_test.py` |
| 1 kHz loop, emulated ESC | board | `sudo taskset -c 1 $PY host/run_controller.py --sim --policy vqc --pl ../overlay/vqc_can0.bit` |
| Bus scan / info / calibrate | board | `$PY host/recoil_cli.py [--channel /dev/ttyACM0] scan` · `info 1` · `calibrate 1` |
| Open-loop drive (no encoder) | board + ESC with `recoil_openloop*.elf` | `sudo taskset -c 1 $PY host/openloop_run.py --channel /dev/ttyACM0 --amp 0.3 --voltage 1.0 --duration 20 --log /tmp/ol.csv` |
| Closed loop (needs encoder) | board + ESC with `recoil_normal.elf` | `sudo taskset -c 1 $PY host/run_controller.py --id 1 --policy pd --amp 0.05` → `--policy vqc` → `--policy vqc --pl ...` |
| Website + self test | PC | `cd website && python -m http.server 8765`; `python website/tools/verify_site.py [--shots]` |
| Website tour video | PC | `python website/tools/record_tour.py` (needs `python -m playwright install ffmpeg`) |
| Document checks | PC | `python docs/tools/check_docs.py` |

`--channel` accepts a SocketCAN interface (`can0`, default) or an slcan serial device (`/dev/ttyACM0`, CANable).
`run_controller.py` writes `gear_ratio = -15` to the ESC and scales kp, kd, the torque limit and τ_ff by 15
(firmware units are motor-side; see report §5.19). Calibration is not stored across power cycles
(`LOAD_*_FROM_FLASH = 0`), so calibrate after every power-up.

## 6. Conventions

- Results go into `docs/results/results.json` (+ raw logs in `docs/results/logs/`); figures are generated from it.
  Report only measured values as results; mark predictions/estimates explicitly; keep negative results.
- The PYNQ copy of the code (`~/vqc_ctrl`) is a deployment target; edit in this repository and copy over.
- Generated files (docx/pptx, website screenshots, firmware objects, Vivado/HLS projects) are not committed; see `.gitignore`.

## 7. Known pitfalls

| Symptom | Cause / fix |
|---|---|
| `DEV_USB_COMM_ERR`, `Unable to get core ID` on a new board | Factory ST-LINK V2J28 — upgrade (`STLinkUpgrade.jar -sn <SN> -update`) right after re-plugging USB |
| Boots into the system bootloader | Option bytes: `nSWBOOT0=0 nBOOT0=1` |
| HardFault after flashing | Used `--start`; do a separate `-hardRst`. With `LOAD_*_FROM_FLASH=1` the zero-struct store bug also faults |
| LED dark, CAN and UART silent | Firmware waiting for the encoder — fit an AS5600 or use the open-loop build |
| CAN bus-off with bit errors | Transceiver not driving the bus: power, Pmod pins, 5 V-only transceiver chips |
| ESC never sees frames / sees garbage | CANH/CANL swapped, missing GND between boards, loose pad contact |
| Bit1 errors when the ESC replies | No termination — PC14 high (default in this repo) |
| ESC receives pings but answers late or never | Stale RX FIFO frames — fixed by draining the FIFO in the callback (in this repo) |
| PL core does not answer after reboot | `bootpy.service` overwrote the PL — run the overlay service after it |
| Old replies mistaken for new | Recoil has no sequence numbers — the host drains RX before each request |
| HLS core correct in co-simulation, wrong on the board | double-precision tanh/exp path; transcendentals are computed on the PS (unexplained, report §5.17) |
