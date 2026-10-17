"""1 kHz single-joint controller on the PYNQ PS: residual VQC feed-forward over CAN.

Firmware runs MODE_POSITION (PD at 2 kHz); every 1 ms the host sends RPDO3
[q_ref, tau_ff] and receives [q, torque]. tau_ff comes from --policy:
    pd        tau_ff = 0 (firmware PD only)
    mlp       MLP 6-8-1 baseline (65 weights, vqc/runs/mlp_8_s0.json)
    model_ff  nominal inverse-dynamics feed-forward (classical baseline)
    vqc       6-qubit VQC (C kernel via ctypes, or the PL IP when available)

Targets are relative to the joint position at start-up and ramp in over 1 s.
Safety: tracking error > --err-limit or any exception -> MODE_DAMPING -> IDLE.

    python3 run_controller.py --sim --policy vqc            # no hardware
    python3 run_controller.py --id 1 --policy vqc --amp 0.3  # real ESC on can0
"""
from __future__ import annotations

import argparse
import csv
import gc
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "vqc"))

import actuator_sim as A  # noqa: E402
import recoil as R  # noqa: E402

PERIOD = A.DT_CTRL
PDO_TIMEOUT = 0.8e-3          # reply budget inside the 1 ms period
MAX_MISSED_IN_A_ROW = 5


class MLPPolicy:
    """MLP 6-8-1 baseline (vqc/train.py make_mlp_policy): same encoded inputs and squashing as the VQC."""

    def __init__(self, path):
        import json
        import numpy as np
        import vqc_model as M
        d = json.load(open(path))
        th = np.asarray(d["theta"], dtype=np.float64)
        sizes = [M.N_QUBITS, 8, 1]
        self.layers, k = [], 0
        for i, o in zip(sizes[:-1], sizes[1:]):
            W = th[k:k + o * i].reshape(o, i); k += o * i
            b = th[k:k + o]; k += o
            self.layers.append((W, b))
        self.M, self.np = M, np
        self.backend = "numpy"

    def __call__(self, obs):
        np, M = self.np, self.M
        h = np.pi * np.tanh(M.FEAT_SCALE * np.asarray(obs, dtype=np.float64)[list(M.FEAT_INDEX)])
        for j, (W, b) in enumerate(self.layers):
            h = W @ h + b
            if j < len(self.layers) - 1:
                h = np.tanh(h)
        return M.TAU_MAX * float(np.tanh(M.OUT_GAIN * h[0]))


def make_policy(name, params_path, pl_bitfile=None):
    if name == "pd":
        return lambda obs: 0.0, "pd"
    if name == "model_ff":
        return A.model_ff, "model_ff"
    if name == "mlp":
        return MLPPolicy(os.path.join(HERE, "..", "vqc", "runs", "mlp_8_s0.json")), "mlp[65]"
    if pl_bitfile:
        from vqc_pl import VQCPolicyPL
        pol = VQCPolicyPL(pl_bitfile, params_path)
    else:
        from vqc_runtime import VQCPolicy
        pol = VQCPolicy.from_json(params_path)
    return pol, f"vqc[{pol.backend}]"


def try_realtime():
    try:
        os.sched_setscheduler(0, os.SCHED_FIFO, os.sched_param(80))
        return "SCHED_FIFO/80"
    except (PermissionError, AttributeError, OSError):
        return "SCHED_OTHER (run with sudo for SCHED_FIFO)"


def percentile(xs, p):
    s = sorted(xs)
    return s[min(len(s) - 1, int(p * len(s)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", type=int, default=1)
    ap.add_argument("--channel", default="can0")
    ap.add_argument("--sim", action="store_true", help="in-process emulated ESC + joint, no CAN")
    ap.add_argument("--policy", choices=("pd", "model_ff", "vqc", "mlp"), default="vqc")
    ap.add_argument("--params", default=os.path.join(HERE, "..", "vqc", "vqc_params.json"))
    ap.add_argument("--pl", metavar="BITFILE", default=None, help="run the VQC on the PL core (vqc_can0.bit)")
    ap.add_argument("--traj", choices=("sine", "chirp", "step"), default="sine")
    ap.add_argument("--amp", type=float, default=0.3)
    ap.add_argument("--freq", type=float, default=0.5)
    ap.add_argument("--duration", type=float, default=6.0)
    ap.add_argument("--kp", type=float, default=A.FIRMWARE_PD["kp"])
    ap.add_argument("--kd", type=float, default=A.FIRMWARE_PD["kd"])
    ap.add_argument("--torque-limit", type=float, default=A.TORQUE_LIMIT)
    ap.add_argument("--gear-ratio", type=float, default=-15.0,
                    help="written to the firmware; positions/torques are then output-shaft quantities "
                         "(motor_configuration.json uses -15; firmware default is 1)")
    ap.add_argument("--err-limit", type=float, default=0.3, help="abort if |q_ref - q| exceeds this [rad]")
    ap.add_argument("--log", default=None, help="CSV output path")
    args = ap.parse_args()

    if args.sim:
        from recoil_emulator import DirectTransport, FakeRecoil
        bus = R.RecoilBus(DirectTransport([FakeRecoil(args.id, A.Joint())]))
    else:
        bus = R.RecoilBus(channel=args.channel)
    policy, policy_name = make_policy(args.policy, args.params, args.pl)
    sched = try_realtime()

    bus.flush()
    if not bus.ping(args.id, timeout=0.1):
        sys.exit(f"device {args.id} did not answer ping on {'sim' if args.sim else args.channel}")
    info = bus.info(args.id)
    print("device:", info)
    if info["mode"] not in ("IDLE", "DAMPING"):
        sys.exit(f"device in mode {info['mode']}, expected IDLE")

    # Units: the policies and gains are defined like the training model (output-shaft angle,
    # motor-side torque). With gear_ratio g = +-15 the firmware works in the output frame and
    # its torque is output-side, i.e. |g| times the model torque -> scale gains and torques.
    G = abs(args.gear_ratio)
    bus.write_f32(args.id, R.PARAM_GEAR_RATIO, args.gear_ratio)
    bus.write_f32(args.id, R.PARAM_POSITION_KP, args.kp * G)
    bus.write_f32(args.id, R.PARAM_VELOCITY_KP, args.kd * G)
    bus.write_f32(args.id, R.PARAM_TORQUE_LIMIT, args.torque_limit * G)
    if abs(G - 15.0) > 1e-6:
        print(f"warning: |gear_ratio| = {G} != 15 -> positions are not output-shaft radians")
    q0 = bus.read_f32(args.id, R.PARAM_POSITION_MEASURED)
    bus.pdo_position_torque(args.id, q0, 0.0)
    bus.set_mode(args.id, R.MODE_POSITION)
    print(f"policy={policy_name} traj={args.traj} amp={args.amp} freq={args.freq} kp={args.kp} kd={args.kd} "
          f"(firmware: gear {args.gear_ratio}, kp {args.kp * G:.2f}, kd {args.kd * G:.3f}) "
          f"q0={q0:+.4f} sched={sched}", flush=True)

    obsb = A.ObsBuilder()
    n = int(args.duration / PERIOD)
    log = []
    periods, compute_us, rtt_us = [], [], []
    q, q_prev, qd = q0, q0, 0.0
    tau_meas, missed, miss_run = 0.0, 0, 0
    status = "ok"
    gc.collect()
    gc.disable()                                  # no GC pauses inside the 1 kHz loop
    t_start = time.perf_counter()
    t_next = t_start
    t_last = None
    try:
        for k in range(n):
            # --- wait for the next 1 ms tick (sleep, then spin the last 300 us)
            t_next += PERIOD
            while True:
                rem = t_next - time.perf_counter()
                if rem <= 0:
                    break
                if rem > 3e-4:
                    time.sleep(rem - 3e-4)
            now = time.perf_counter()
            if t_last is not None:
                periods.append(now - t_last)
            t_last = now
            t = k * PERIOD

            ramp = min(1.0, t / 1.0)
            r, rd = A.reference(t, args.traj, args.amp, args.freq)
            q_ref, qd_ref = q0 + ramp * r, ramp * rd

            c0 = time.perf_counter()
            obs = obsb(q, qd, q_ref, qd_ref)
            obs[4] = q_ref - q0                       # reference relative to start
            tau_ff = float(policy(obs)) * ramp
            obsb.commit(tau_ff)
            compute_us.append((time.perf_counter() - c0) * 1e6)

            try:
                c1 = time.perf_counter()
                q, tau_meas = bus.pdo_position_torque(args.id, q_ref, tau_ff * G, timeout=PDO_TIMEOUT)
                tau_meas /= G
                rtt_us.append((time.perf_counter() - c1) * 1e6)
                miss_run = 0
            except R.RecoilTimeout:
                # Recoil runs without CAN auto-retransmission: tolerate isolated lost
                # replies (hold the last measurement), abort on a sustained outage.
                missed += 1
                miss_run += 1
                if miss_run >= MAX_MISSED_IN_A_ROW:
                    status = f"ABORT: {miss_run} PDO replies missed in a row at t={t:.3f}s"
                    break
            qd = 0.7 * qd + 0.3 * (q - q_prev) / PERIOD   # host-side velocity estimate
            q_prev = q
            log.append((t, q_ref, q, qd, tau_ff, tau_meas))
            if abs(q_ref - q) > args.err_limit:
                status = f"ABORT: tracking error {q_ref - q:+.3f} rad at t={t:.3f}s"
                break
    except KeyboardInterrupt:
        status = "interrupted"
    except Exception as e:  # noqa: BLE001 - any failure must leave the joint safe
        status = f"ABORT: {type(e).__name__}: {e}"
    finally:
        gc.enable()
        bus.set_mode(args.id, R.MODE_DAMPING)
        time.sleep(0.3)
        bus.set_mode(args.id, R.MODE_IDLE)

    elapsed = time.perf_counter() - t_start
    err = [row[1] - row[2] for row in log[1000:]] or [row[1] - row[2] for row in log]
    jit = [abs(p - PERIOD) * 1e6 for p in periods]
    print(f"status: {status}")
    print(f"ticks: {len(log)} in {elapsed:.2f}s  "
          f"rms err: {1e3 * math.sqrt(sum(e * e for e in err) / max(1, len(err))):.2f} mrad  "
          f"max err: {1e3 * max(abs(e) for e in err):.2f} mrad  missed replies: {missed}")
    if jit:
        print(f"period jitter: p50 {percentile(jit, .5):.1f} us  p99 {percentile(jit, .99):.1f} us  "
              f"max {max(jit):.1f} us   overruns(>1.5ms): {sum(p > 1.5 * PERIOD for p in periods)}")
        print(f"policy compute: p50 {percentile(compute_us, .5):.1f} us  p99 {percentile(compute_us, .99):.1f} us")
    if rtt_us:
        print(f"PDO round trip: p50 {percentile(rtt_us, .5):.1f} us  p99 {percentile(rtt_us, .99):.1f} us  "
              f"max {max(rtt_us):.1f} us")
    if args.log:
        with open(args.log, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["t", "q_ref", "q", "qd_est", "tau_ff", "tau_meas"])
            w.writerows(log)
        print("log:", args.log)
    return 0 if status in ("ok", "interrupted") else 1


if __name__ == "__main__":
    sys.exit(main())
