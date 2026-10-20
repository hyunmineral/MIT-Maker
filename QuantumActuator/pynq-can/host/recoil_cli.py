"""Recoil bring-up / maintenance CLI over SocketCAN.

    python3 recoil_cli.py scan
    python3 recoil_cli.py info 1
    python3 recoil_cli.py mode 1 idle|damping|position|disabled
    python3 recoil_cli.py calibrate 1          # MODE_CALIBRATION, waits until back in IDLE
    python3 recoil_cli.py get 1 position_kp
    python3 recoil_cli.py set 1 position_kp 20
    python3 recoil_cli.py store 1              # write config to flash
    python3 recoil_cli.py watch 1              # stream position at ~20 Hz (joint in IDLE)
"""
from __future__ import annotations

import argparse
import sys
import time

import recoil as R

PARAMS = {k[6:].lower(): v for k, v in vars(R).items() if k.startswith("PARAM_")}
U32_PARAMS = {"device_id", "firmware_version", "watchdog_timeout", "fast_frame_frequency", "mode", "error",
              "motor_pole_pairs"}
MODES = {"disabled": R.MODE_DISABLED, "idle": R.MODE_IDLE, "damping": R.MODE_DAMPING,
         "calibration": R.MODE_CALIBRATION, "torque": R.MODE_TORQUE, "velocity": R.MODE_VELOCITY,
         "position": R.MODE_POSITION}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--channel", default="can0")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scan")
    for c in ("info", "calibrate", "store", "watch"):
        sub.add_parser(c).add_argument("id", type=int)
    p = sub.add_parser("mode"); p.add_argument("id", type=int); p.add_argument("mode", choices=MODES)
    p = sub.add_parser("get"); p.add_argument("id", type=int); p.add_argument("param", choices=PARAMS)
    p = sub.add_parser("set"); p.add_argument("id", type=int); p.add_argument("param", choices=PARAMS)
    p.add_argument("value", type=float)
    a = ap.parse_args()

    bus = R.RecoilBus(channel=a.channel, timeout=0.05)
    if a.cmd == "scan":
        ids = bus.scan()
        print("devices:", ids or "none (check wiring, 120 ohm termination, ESC power, bitrate)")
        return 0 if ids else 1
    if not bus.ping(a.id, timeout=0.1):
        print(f"device {a.id} not responding")
        return 1
    if a.cmd == "info":
        for k, v in bus.info(a.id).items():
            print(f"  {k:14s} {v}")
    elif a.cmd == "mode":
        bus.set_mode(a.id, MODES[a.mode])
        time.sleep(0.05)
        print("mode:", R.MODE_NAMES.get(bus.read_u32(a.id, R.PARAM_MODE)))
    elif a.cmd == "calibrate":
        print("calibrating: the motor will turn slowly, keep the joint free ...")
        bus.set_mode(a.id, R.MODE_CALIBRATION)
        t0 = time.time()
        while time.time() - t0 < 60:
            time.sleep(0.5)
            try:
                mode = bus.read_u32(a.id, R.PARAM_MODE)
            except R.RecoilTimeout:
                continue
            if mode != R.MODE_CALIBRATION:
                print(f"done in {time.time() - t0:.1f}s, mode={R.MODE_NAMES.get(mode)}, flux_offset="
                      f"{bus.read_f32(a.id, R.PARAM_ENCODER_FLUX_OFFSET):.6f}; run 'store' to keep it")
                break
        else:
            print("calibration did not finish within 60 s")
            return 1
    elif a.cmd in ("get", "set"):
        off = PARAMS[a.param]
        if a.cmd == "set":
            (bus.write_u32 if a.param in U32_PARAMS else bus.write_f32)(a.id, off, int(a.value) if a.param in U32_PARAMS else a.value)
            time.sleep(0.01)
        v = bus.read_u32(a.id, off) if a.param in U32_PARAMS else bus.read_f32(a.id, off)
        print(f"{a.param} = {v}")
    elif a.cmd == "store":
        bus.store_config(a.id)
        print("store requested (firmware writes flash page 63)")
    elif a.cmd == "watch":
        try:
            while True:
                print(f"\rpos {bus.read_f32(a.id, R.PARAM_POSITION_MEASURED):+9.4f} rad  "
                      f"vel {bus.read_f32(a.id, R.PARAM_VELOCITY_MEASURED):+8.3f} rad/s  "
                      f"Vbus {bus.read_f32(a.id, R.PARAM_BUS_VOLTAGE_MEASURED):5.2f} V", end="", flush=True)
                time.sleep(0.05)
        except KeyboardInterrupt:
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
