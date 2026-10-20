"""Virtual Recoil device on a SocketCAN interface (simulated joint behind it).

With can0 in controller loopback mode, frames sent by run_controller.py go
through the Zynq CAN controller at 1 Mbps and reach this process, which replies
like the firmware. This exercises the real CAN path end-to-end without the ESC:

    sudo ip link set can0 down
    sudo ip link set can0 type can bitrate 1000000 sample-point 0.8 loopback on
    sudo ip link set can0 up
    python3 virtual_recoil.py --id 1 &
    python3 run_controller.py --id 1 --policy vqc
"""
from __future__ import annotations

import argparse
import signal
import time

import recoil as R
from recoil_emulator import FakeRecoil
from actuator_sim import Joint  # noqa: E402  (path set by recoil_emulator)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--channel", default="can0")
    ap.add_argument("--id", type=int, default=1)
    ap.add_argument("--J", type=float, default=None, help="override joint inertia")
    ap.add_argument("--delay", type=int, default=None, help="command delay [ms]")
    args = ap.parse_args()

    joint = Joint()
    if args.J is not None:
        joint.J = args.J
    if args.delay is not None:
        joint.delay = args.delay
    dev = FakeRecoil(args.id, joint, step_on_pdo=False)
    t = R.SocketCANTransport(args.channel, rx_funcs=R.DEVICE_RX_FUNCS)
    running = [True]
    signal.signal(signal.SIGTERM, lambda *_: running.__setitem__(0, False))
    print(f"virtual Recoil id={args.id} on {args.channel} (J={joint.J}, delay={joint.delay} ms)", flush=True)
    # Like the firmware: replies go out immediately, the joint advances on wall-clock
    # time (1 ms steps) with the latest command, so a slow moment never builds a backlog.
    t_sim = time.perf_counter()
    try:
        while running[0]:
            f = t.recv(2e-4)
            while f is not None:
                if f.can_id >= 0:
                    reply = dev.handle(f.can_id, f.data.ljust(8, b"\0"))
                    if reply:
                        t.send(*reply)
                f = t.recv(0)
            n = int((time.perf_counter() - t_sim) / 1e-3)
            if n:
                dev.advance(min(n, 50))
                t_sim += n * 1e-3
    except KeyboardInterrupt:
        pass
    finally:
        t.close()


if __name__ == "__main__":
    main()
