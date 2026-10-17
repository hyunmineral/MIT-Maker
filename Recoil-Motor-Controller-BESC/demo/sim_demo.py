"""Check the DEMO_STANDALONE gains on the project's joint model before trying them on hardware.

Same plant and randomization ranges as pynq-can/vqc/actuator_sim.py (output-side J, b, tau_c, eta;
motor-side torque), but with the demo's firmware settings:
  - gear_ratio 1 in firmware -> convert: kp_model = DEMO_KP * 15, kd_model = DEMO_KD * 15 (output units)
  - torque_limit 0.3 N*m (motor side), EMA alpha 0.145 (firmware default; the host normally sets 0.27)
  - target recomputed every 5 ms in APP_main (held in between), 2 s amplitude ramp
  - trip if |target - q| > 1.5 motor rad (= 0.1 output rad)

    python sim_demo.py
"""
import math
import random

GEAR = 15.0
H = 0.5e-3                                # firmware position loop 2 kHz
QD_LIMIT = 18.0
DEMO = dict(amp=4.5 / GEAR, freq=0.25, ramp=2.0, kp=0.5 * GEAR, kd=0.01 * GEAR,
            tlim=0.3, alpha=0.145, trip=1.5 / GEAR, t_end=12.0, hold=5e-3)
RANDOM = dict(J=(0.007, 0.028), b=(0.02, 0.10), tau_c=(0.05, 0.40), eta=(0.75, 0.92))
NOMINAL = dict(J=0.014, b=0.05, tau_c=0.20, eta=0.85)


def run(p, d=DEMO):
    q = qd = tau_m = 0.0
    target = 0.0
    n_hold = int(round(d["hold"] / H))
    errs, peak_tau = [], 0.0
    for k in range(int(d["t_end"] / H)):
        t = k * H
        if k % n_hold == 0:
            ramp = min(t / d["ramp"], 1.0)
            target = ramp * d["amp"] * math.sin(2 * math.pi * d["freq"] * t)
        tau = d["kp"] * (target - q) - d["kd"] * qd
        tau_m = max(-d["tlim"], min(d["tlim"], tau_m + d["alpha"] * (tau - tau_m)))
        peak_tau = max(peak_tau, abs(tau_m))
        qdd = (GEAR * p["eta"] * tau_m - p["b"] * qd - p["tau_c"] * math.tanh(qd / 0.05)) / p["J"]
        qd = max(-QD_LIMIT, min(QD_LIMIT, qd + qdd * H))
        q += qd * H
        errs.append(target - q)
    tail = errs[int(d["ramp"] / H):]
    return dict(max_err=max(abs(e) for e in errs), rms=math.sqrt(sum(e * e for e in tail) / len(tail)),
                peak_tau=peak_tau, tripped=max(abs(e) for e in errs) > d["trip"])


if __name__ == "__main__":
    r = run(NOMINAL)
    print(f"nominal: max err {r['max_err']*1e3:.1f} mrad, RMS {r['rms']*1e3:.1f} mrad, "
          f"peak torque {r['peak_tau']:.2f} N*m (limit {DEMO['tlim']}), trip {r['tripped']}")
    rng = random.Random(0)
    res = [run({k: rng.uniform(*v) for k, v in RANDOM.items()}) for _ in range(256)]
    trips = sum(x["tripped"] for x in res)
    worst = max(x["max_err"] for x in res)
    sat = sum(x["peak_tau"] >= DEMO["tlim"] - 1e-9 for x in res)
    print(f"random 256: trips {trips}, worst max err {worst*1e3:.1f} mrad (trip {DEMO['trip']*1e3:.0f}), "
          f"median RMS {sorted(x['rms'] for x in res)[128]*1e3:.1f} mrad, torque saturated in {sat}")
