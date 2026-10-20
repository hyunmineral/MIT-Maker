"""Open-loop drive of the joint over CAN, for the encoder-less firmware build
(Recoil-Motor-Controller-BESC/demo/recoil_openloop.elf, OPENLOOP_NO_ENCODER=1).

The ESC rotates a voltage vector to the commanded angle and the rotor follows like a stepper.
Nothing is measured except the phase current, so this proves the PYNQ -> CAN -> ESC -> motor path
and measures the real bus timing; it is NOT a control experiment.

    sudo taskset -c 1 $PY openloop_run.py --id 1 --amp 0.1 --voltage 0.8 --log /tmp/openloop.csv

RPDO3 in this firmware: [angle target, voltage amplitude] -> TPDO3: [applied angle, |i_phase|].
The firmware keeps gear_ratio = 1, so angles on the wire are motor radians; this script takes
output-shaft amplitudes and multiplies by --gear.
"""
from __future__ import annotations

import argparse
import csv
import gc
import math
import statistics
import time

import recoil as R


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--channel", default="can0")
    ap.add_argument("--id", type=int, default=1)
    ap.add_argument("--amp", type=float, default=0.1, help="output-shaft amplitude [rad]")
    ap.add_argument("--freq", type=float, default=0.25, help="sine frequency [Hz]")
    ap.add_argument("--voltage", type=float, default=0.8, help="voltage amplitude [V], firmware clamps to 2.0")
    ap.add_argument("--duration", type=float, default=10.0, help="[s]")
    ap.add_argument("--rate", type=float, default=200.0, help="command rate [Hz]")
    ap.add_argument("--gear", type=float, default=15.0)
    ap.add_argument("--ramp", type=float, default=2.0, help="voltage/amplitude fade-in [s]")
    ap.add_argument("--log", default=None)
    args = ap.parse_args()

    bus = R.RecoilBus(channel=args.channel)
    if not bus.ping(args.id, timeout=0.05):
        print(f"device {args.id} does not answer (CAN wiring? firmware stuck waiting for an encoder?)")
        return 1
    info = bus.info(args.id)
    print("device:", info)

    bus.set_mode(args.id, R.MODE_IDLE)
    bus.pdo_position_torque(args.id, 0.0, 0.0, timeout=0.01)        # command origin, 0 V
    bus.set_mode(args.id, R.MODE_VALPHABETA_OVERRIDE)
    time.sleep(0.02)
    mode = bus.read_u32(args.id, R.PARAM_MODE)
    if mode != R.MODE_VALPHABETA_OVERRIDE:
        print(f"firmware refused open-loop mode (mode = 0x{mode:02X}); is recoil_openloop.elf flashed?")
        bus.set_mode(args.id, R.MODE_IDLE)
        return 1

    period = 1.0 / args.rate
    rows, rtts, misses = [], [], 0
    gc.disable()
    t0 = time.perf_counter()
    next_t = t0
    try:
        while True:
            t = time.perf_counter() - t0
            if t > args.duration:
                break
            ramp = min(t / args.ramp, 1.0)
            # fade out during the last ramp period too
            ramp = min(ramp, max((args.duration - t) / args.ramp, 0.0))
            q_out = ramp * args.amp * math.sin(2 * math.pi * args.freq * t)
            volt = ramp * args.voltage
            s = time.perf_counter()
            try:
                applied, current = bus.pdo_position_torque(args.id, q_out * args.gear, volt, timeout=0.002)
                rtts.append((time.perf_counter() - s) * 1e6)
                rows.append((t, q_out, applied / args.gear, volt, current))
            except R.RecoilTimeout:
                misses += 1
                if misses > 20:
                    print("too many missed replies, stopping")
                    break
            next_t += period
            time.sleep(max(0.0, next_t - time.perf_counter()))
    finally:
        gc.enable()
        bus.set_mode(args.id, R.MODE_DAMPING)
        time.sleep(0.3)
        bus.set_mode(args.id, R.MODE_IDLE)

    if args.log:
        with open(args.log, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["t", "q_cmd_out", "q_applied_out", "voltage", "i_phase"])
            w.writerows(rows)
    if rtts:
        rs = sorted(rtts)
        cur = [r[4] for r in rows]
        print(f"frames {len(rows)}, missed {misses}, RTT p50 {rs[len(rs)//2]:.0f} us, "
              f"p99 {rs[int(len(rs)*0.99)]:.0f} us, max {rs[-1]:.0f} us")
        print(f"phase current mean {statistics.mean(cur):.2f} A, max {max(cur):.2f} A "
              f"(no current at all -> check motor phases and bus voltage)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
