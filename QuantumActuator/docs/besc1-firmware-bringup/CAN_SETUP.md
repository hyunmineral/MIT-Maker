# CANable v2.0 Setup Guide

**Purpose**: CAN 1 Mbps communication with the Recoil firmware on the B-G431B-ESC1
**Order date**: 2026-09-20
**PC**: Windows 11 (<repo root>)

---

> **Status (2026-10-13)**: The working path is **PYNQ USB → CANable 2.0 (slcan, `/dev/ttyACM0`) → ESC** (`SlcanTransport` in `recoil.py`). With an RTT p50 of 1.81 ms it is too slow for 1 kHz, and **the PS CAN0 + SN65HVD230 path does not work**. Details in §5.
>
> **(Historical note) Update (2026-10-06) — the main path at the time was PYNQ-Z2 PS CAN**
>
> The CANable was not connected yet, and the ESC control host was moved to the PYNQ-Z2. The implementation and verification results are in `pynq-can/README.md` and `docs/actuator-vqc-control-report.md` §3.3, §4.7.
>
> | Item | Status |
> |---|---|
> | PYNQ `can0` (Zynq PS CAN0, `xilinx_can`) | ✅ Automatically enabled at boot via a device tree overlay + systemd service. 1 Mbps, sample point 0.8 (same as Recoil), reference clock 100 MHz |
> | Pins | ✅ `can0.bit` / `vqc_can0.bit`: CAN0 → EMIO → Pmod JA (JA1 = TX/Y18, JA2 = RX/Y19, pull-up) |
> | Transceiver | ⏳ SN65HVD230 module not wired. Pmod JA pin 6 = 3V3, pin 5 = GND, CTX ← JA1, CRX → JA2. Only CANH/CANL and GND go to the ESC CAN connector (the ESC has a built-in transceiver; 5V pin not connected). Confirm CANH–CANL ≈ 60 Ω — `BOARD_REPLACEMENT.md` §8~9 |
> | Host code | ✅ `pynq-can/host/recoil.py`: uses only the standard `socket.AF_CAN`, so python-can is not needed. Diagnostic `recoil_cli.py scan/info/mode/calibrate/get/set/store/watch` |
> | Verification | Controller loopback 5000/5000. Transmitting in normal mode without a transceiver gives bit errors followed by bus-off (evidence that the pin path is alive) |
>
> **If using the CANable** (historical note from 2026-10-06, resolved on 10-13: a CANable with slcan firmware is recognized as `/dev/ttyACM0` and is used directly from the PYNQ with `SlcanTransport`): The PYNQ kernel has neither `gs_usb` nor `slcan`, so plugging the CANable into the PYNQ USB does not get it recognized. Use the CANable on the **Windows PC** following the procedure below. If you put a transport that wraps a python-can `gs_usb` bus in place of `SocketCANTransport` in `recoil.py`, the same upper-layer code can be used as is (only three methods need to be implemented: `send(can_id, data)`, `recv(timeout)`, `close()`).
>
> The Lowlevel repository (`berkeley_humanoid_lite_lowlevel`) in §6 below was not used because the submodule is empty. The protocol was implemented in `recoil.py` by reading the firmware's `motor_controller.c` directly.

---

## 1. CANable v2.0 Overview

- **MCU**: STM32G431 (same family as the B-G431B-ESC1)
- **CAN transceiver**: MCP2551 or TCAN330 family
- **USB PID/VID**: `1D50:606F` with the default candleLight FW
- **Supported firmware** (user-selectable):
  - **candleLight**: recognized by the kernel-native `gs_usb` driver → python-can `gs_usb` interface (**recommended on Windows**)
  - **slcan**: recognized as a virtual COM port → python-can `slcan` interface
  - **candleLight PRO**: improved version of candleLight

**Recommended**: candleLight — on Windows, just install the WinUSB driver with Zadig and python-can recognizes it right away. slcan needs separate COM port baud/latency tuning.

---

## 2. Firmware Check/Change (immediately on arrival)

### 2.1 Check which firmware is flashed

After plugging in USB, in PowerShell:
```powershell
Get-PnpDevice | Where-Object { $_.InstanceId -match 'VID_1D50' } | Format-Table Status, FriendlyName, InstanceId
```

- `PID_606F` → candleLight (usable as is)
- `PID_60C4` or another value → slcan or other FW

### 2.2 If candleLight is already flashed → go to the next step

### 2.3 If it is other FW, replace it with candleLight (DFU method)

1. **Enter DFU mode**: connect USB while holding the CANable v2.0's BOOT button (or use the BOOT switch)
2. Confirm DFU recognition on Windows:
   ```powershell
   Get-PnpDevice | Where-Object { $_.InstanceId -match 'VID_0483.*PID_DF11' }
   ```
3. Firmware download: https://canable.io/updater/canable2.html (web-based DFU flasher)
   - Select "candleLight" → click "Update"
   - Or download the `.bin` directly from GitHub: https://github.com/candle-usb/candleLight_fw/releases

---

## 3. Windows Driver (Zadig — once only, on first use)

candleLight does not yet have a kernel-native driver on Windows, so it must be rebound to the **WinUSB** driver before python-can can use it.

1. Download Zadig: https://zadig.akeo.ie/
2. Run as administrator
3. Check **Options → List All Devices**
4. Select **"gs_usb (Interface 0)"** or **"CANable"** from the dropdown
5. Change the driver to **WinUSB (v6.1.7600.16385)**
6. Click **Install Driver** → re-plug USB when done

Check:
```powershell
Get-PnpDevice | Where-Object { $_.InstanceId -match 'VID_1D50.*PID_606F' } | Format-Table Status
# Status must be OK
```

---

## 4. python-can Installation and Test

### 4.1 Installation

```powershell
pip install "python-can[gs_usb]"
pip install pyusb libusb
```

### 4.2 Minimal sanity script (checks only the adapter, without a bus)

`docs/besc1-firmware-bringup/test_canable.py`:
```python
import can
import time

# candleLight (gs_usb) interface
bus = can.Bus(
    interface="gs_usb",
    channel=0,          # first CANable
    bitrate=1_000_000,  # Recoil uses 1 Mbps
)

print(f"Bus initialized: {bus}")
print("Waiting 5 seconds for any RX frames...")
try:
    for _ in range(5):
        msg = bus.recv(timeout=1.0)
        if msg:
            print(f"RX: {msg}")
        else:
            print("  (idle)")
except KeyboardInterrupt:
    pass
finally:
    bus.shutdown()
```

Running it with only the CANable plugged in should print "idle" 5 times without errors.

---

## 5. Physical Wiring to the B-G431B-ESC1

> 🔎 **Bidirectional diagnosis (2026-10-13) (new ESC, open-loop firmware)**
> - The ESC FDCAN1 setting is NBTP 0x000F0601 (prescaler 16, seg1 7, seg2 2 → 1 Mbps, SP 0.8), matching the PYNQ.
> - While the PYNQ was transmitting, the ESC's ECR/PSR = 0 / LEC 7 (no change), bus idle → **the PYNQ signal is not reaching the bus**.
> - Via SWD, 100 was written to `controller.fast_frame_frequency` in RAM so that the ESC sends TPDO4 at 100 Hz. As a result the ESC showed TEC 128, LEC 3 (ACK error), error-passive state → **the ESC transmitter is fine**.
> - During the same time the PYNQ received 0 frames and 0 errors. The PYNQ's own transmissions go BUS-OFF due to bit errors.
> - Conclusion: **the SN65HVD230 module on the PYNQ side neither transmits nor receives.** Candidate causes are no power (3V3) to the module, wrong Pmod JA pin positions, or a faulty module. If the module were alive and only the bus wires were disconnected, the PYNQ should have shown ACK errors, not bit errors.
> - **Same day, switched to the CANable 2.0 (PYNQ USB → CANable → ESC)**: The CANable is recognized with slcan firmware (`/dev/ttyACM0`, version `16e7497 normaldotcom/canable2`) and responds to the `V` command (the adapter is alive). Since the PYNQ has no slcan kernel module, pyserial, or python-can, **`SlcanTransport`** (standard library termios) was added to `recoil.py`. It can now be used with `--channel /dev/ttyACM0`.
>   - Result: no scan response. 0 lines received by the CANable during 8 seconds of the ESC transmitting at 100 Hz. The ESC reports ACK errors (LEC 3, error-passive).
>   - The ESC's ACK errors mean the ESC transceiver is driving the bus and reading back its own signal correctly (if it were in standby, there should have been bit errors).
>   - **No frames exchanged with the ESC on either adapter (SN65HVD230 module, CANable)** → the common segment, **the CANH/CANL wiring on the ESC side** (ESC CAN terminal pin positions, contact, connection to a different terminal), is the most likely cause.
> - **Resolution (same day)** — four causes were overlapping.
>   1. Poor contact on the ESC CAN pads: the user soldered on a pin header. After soldering, SWD and the firmware were fine.
>   2. One CAN wire was disconnected.
>   3. **CANH/CANL were swapped.** After swapping them, the ESC received frames for the first time (REC increasing). With reversed polarity, the ESC saw nothing (REC 0).
>   4. **No termination**: With PC14 LOW (upstream default), Bit1 errors → BUS-OFF occurred when the ESC responded. Writing GPIOC ODR bit14 = 1 (PC14 HIGH) via SWD made the errors disappear → judged that **PC14 HIGH = ESC 120 Ω termination ON** (not a direct resistance measurement).
> - **Firmware bug fix**: While errors were piling up, 2 unprocessed frames were left in RX FIFO0. The upstream callback reads only 1 frame per interrupt, so every subsequent request was processed as the frame from 2 frames earlier (ping received but no response). → `HAL_FDCAN_RxFifo0Callback` was fixed to drain the FIFO completely. Also, `CAN_TERMINATION_ENABLED` (default 1) sets PC14 HIGH at boot. All 4 builds were rebuilt.
> - **Result**: `recoil_cli.py --channel /dev/ttyACM0 info 1` succeeded over PYNQ → CANable (slcan, `/dev/ttyACM0`) → ESC (ID 1, 0x20250226, IDLE, 0 errors).
>   - `openloop_run.py` run for 5 seconds without motor power: 1000 frames, 0 dropped, **RTT p50 1849 µs / p99 1892 µs / max 3392 µs** (200 Hz commands).
>   - 20-second run with motor power applied (representative values): 4000 frames, 0 dropped, **RTT p50 1806 µs / p99 1966 µs / max 11011 µs**, phase current mean 0.80 A, max 1.37 A, output shaft motion confirmed visually.
>   - Because it goes through USB Full-speed, the round trip is about 1.85 ms → **a 1 kHz loop (1 ms period) is not possible with the CANable.** 1 kHz experiments need the PS CAN + SN65HVD230 path (estimated RTT 350~420 µs, not measured).


> ⚠ **Correction (2026-10-07)** (the termination and pin-order content below has been superseded by the 2026-10-13 results above: PC14 HIGH = ON, and CANH/CANL were swapped in the actual wiring): The "J2 pin?" and "SB18 solder bridge" in this section were unconfirmed guesses. For confirmed information, `BOARD_REPLACEMENT.md` §8~9 takes precedence.
> - The ESC has a built-in CAN transceiver, and CANH/CANL come out on the connector (MCU-side FDCAN1: RX PA11, TX PB9).
> - The CAN connector pin order, per summary material, is GND, CAN L, CAN H, 5V (UM2516 original not checked → confirm with the silkscreen).
> - The ESC 120 Ω termination is switched on and off not by a solder bridge but by the MCU pin CAN_TERM (PC14). Recoil sets it LOW at initialization (`Core/Src/main.c:901`). The polarity is unconfirmed, so measure it.

Connect CAN_H / CAN_L of the CANable v2.0's **DB9 or 2-pin header** to the CAN header of the B-G431B-ESC1:

| CANable v2.0 | B-G431B-ESC1 |
|---|---|
| CAN_H | CAN_H (J2 pin?) |
| CAN_L | CAN_L (J2 pin?) |
| GND | GND (common ground — **mandatory**) |

**Notes**:
- **120Ω terminator resistor required**: with short wiring (<30cm), one end only is fine; if both ends have one, it is seen as 60Ω in parallel and communication still works. The CANable v2.0 usually has a built-in terminator switch (SW1 etc.)
- On the B-G431B-ESC1 side, a 120Ω terminator can also be enabled with a solder bridge (SB18 etc., check the datasheet)
- **Twisted pair recommended** — signal integrity

---

## 6. Preparing the Recoil Host-side Code

### 6.1 Clone the Berkeley Humanoid Lite Lowlevel repository

```powershell
Set-Location <repo root>
git clone https://github.com/HybridRobotics/Berkeley-Humanoid-Lite-Lowlevel.git
Set-Location .\Berkeley-Humanoid-Lite-Lowlevel
pip install -r requirements.txt
pip install -e .
```

### 6.2 Make sure the Recoil Bus interface knows about the CANable

Check the python-can `interface` / `channel` settings in `berkeley_humanoid_lite_lowlevel/recoil/bus.py` (or a similar file). If the default is SocketCAN (Linux), it must be changed to `gs_usb` for Windows:

```python
# Example direction of change (adjust after checking the actual code)
bus = can.Bus(
    interface="gs_usb",     # "socketcan" on Linux
    channel=0,              # "can0" on Linux
    bitrate=1_000_000,
)
```

### 6.3 First communication test — Ping

```powershell
Set-Location Berkeley-Humanoid-Lite-Lowlevel
python .\scripts\motor\ping.py --id 1
# expected output: "Motor is online"
```

**If the "Motor is online" response comes back → everything is working**. It means the firmware is actually responding to the CAN heartbeat in IDLE mode.

**"Motor is offline" → troubleshooting**:
- Check with the candleLight monitor whether frames are actually going out of the CANable
- Check the CAN_H/CAN_L wiring of the B-G431B-ESC1
- Check the 120Ω terminator state
- Check that DEVICE_CAN_ID is 1 (the value flashed into the firmware)
- The watchdog may already have triggered, leaving the firmware in the STOP state → hard reset over USB and ping immediately

---

## 7. First Rotation Test Order

### 7.1 Safety preparation (before applying motor bus power)

- [ ] Actuator output shaft free to rotate (no load)
- [ ] Bench PSU ready: **start with 24V, 2A limit** (110KV × 24V = ~2640 RPM no-load theoretical, 15:1 reduction → 176 RPM)
- [ ] E-stop position secured (PSU main switch)
- [ ] XT30 polarity checked (reverse polarity destroys it instantly)

### 7.2 Step-by-step

1. **Ping succeeds with only USB plugged in** ✓ (step 6.3)
2. **Apply motor bus power** (24V, 2A limit)
3. **Electrical offset calibration**:
   ```powershell
   python .\scripts\motor\calibrate_electrical_offset.py --id 1
   ```
   - During calibration the motor briefly step-rotates from standstill
   - Automatically maps which rotor angle corresponds to the encoder's electrical position 0
   - The stored offset is saved to Flash again via `MotorController_storeConfig` (if LOAD_CALIBRATION_FROM_FLASH=1). We currently have it at 0, so recalibration may be needed on every boot — consider reverting to LOAD_CALIBRATION_FROM_FLASH=1 later for stable use
4. **Open-loop low-speed rotation (Vqd override)**:
   - Use Recoil's `MODE_VQD_OVERRIDE` — command the d/q-axis voltages directly
   - Example: start from v_d = 0, v_q = 0.5V and increase gradually → smooth rotation
5. **Closed-loop torque control**:
   - Enter `MODE_TORQUE` → start from torque_target 0.05 N·m (calculated for the 5010)
6. **Closed-loop velocity control**:
   - `MODE_VELOCITY` → start from velocity_target 1 rad/s
7. **Closed-loop position control**:
   - `MODE_POSITION` → start from position_target 0.1 rad, smooth sinusoidal sweep

At each step, **check the current profile** (watch for spikes on the bench PSU meter). If there is a sharp rise, return to the previous mode immediately.

---

## 8. Checklist on First Arrival

- [x] CANable v2.0 arrived and connected (2026-10-13, PYNQ USB)
- [ ] Plug in USB and check that it is candleLight FW (§2.1)
- [ ] Bind the WinUSB driver with Zadig (§3)
- [ ] `pip install "python-can[gs_usb]"` (§4.1)
- [ ] Adapter sanity check with `test_canable.py` (§4.2)
- [ ] CANable ↔ B-G431B-ESC1 wiring (§5, common GND mandatory)
- [ ] `git clone` Berkeley-Humanoid-Lite-Lowlevel (§6.1)
- [ ] `ping.py --id 1` succeeds (§6.3) — **passing up to here means success**
- [ ] Apply motor bus power → calibration → rotation test (§7)

---

## 9. Key Reference Links

- **CANable v2.0 official**: https://canable.io/
- **candleLight firmware**: https://github.com/candle-usb/candleLight_fw
- **CANable web updater**: https://canable.io/updater/canable2.html
- **Zadig**: https://zadig.akeo.ie/
- **python-can gs_usb docs**: https://python-can.readthedocs.io/en/stable/interfaces/gs_usb.html
- **Berkeley Humanoid Lite Lowlevel** (Python host): https://github.com/HybridRobotics/Berkeley-Humanoid-Lite-Lowlevel

---

## 10. Related Documents

- Firmware setup details: [`README.md`](./README.md) (this folder)
- (Historical note) The plan at the time was to start from §6 after the CANable arrived, but in practice it proceeded on the PYNQ with `recoil.py` + `SlcanTransport` (§5)
