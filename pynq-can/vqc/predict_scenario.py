"""Predictions for the real-hardware test plan (docs/actuator-vqc-control-report-scenario.md).

For each planned trajectory, run PD / model FF / VQC / MLP-65 on N randomized joints
(same plant ranges as training) with the run_controller.py loop (1 s ramp, host-side
velocity estimate) and report RMS / max tracking error percentiles.

    python predict_scenario.py --out ../../docs/results/scenario_predictions.json
"""
import argparse
import json
import math

import torch

import actuator_sim as A
import train as T
import vqc_model as M

TESTS = [  # name, trajectory kind, amplitude [rad], frequency [Hz], seconds
    ("T5 PD small sine", "sine", 0.05, 0.5, 8.0),
    ("T6 sine 0.2 rad 0.5 Hz", "sine", 0.2, 0.5, 8.0),
    ("T6 sine 0.3 rad 1.0 Hz", "sine", 0.3, 1.0, 8.0),
    ("T6 chirp 0.2 rad", "chirp", 0.2, 0.5, 6.0),
]


def ref_batch(kind, amp, freq, steps):
    t = torch.arange(steps) * A.DT_CTRL
    if kind == "sine":
        w = 2 * math.pi * freq
        return amp * torch.sin(w * t), amp * w * torch.cos(w * t)
    f0, k = freq, 0.5
    ph = 2 * math.pi * (f0 * t + 0.5 * k * t * t)
    return amp * torch.sin(ph), amp * 2 * math.pi * (f0 + k * t) * torch.cos(ph)


def run(policy_name, theta, kind, amp, freq, seconds, B, seed):
    gen = torch.Generator().manual_seed(seed)
    p = T.sample_params(B, gen)
    steps = int(seconds / A.DT_CTRL)
    r, rd = ref_batch(kind, amp, freq, steps)
    q = torch.zeros(B); qd_true = torch.zeros(B); tau_m = torch.zeros(B)
    qd_est = torch.zeros(B); q_prev = torch.zeros(B); e_int = torch.zeros(B); tau_prev = torch.zeros(B)
    pipe_q = [torch.zeros(B) for _ in range(3)]; pipe_f = [torch.zeros(B) for _ in range(3)]
    sel = p["delay"][:, None]
    errs = []
    qd_ref_prev = None
    for k in range(steps):
        t = k * A.DT_CTRL
        ramp = min(1.0, t)
        q_ref = ramp * r[k] * torch.ones(B); qd_ref = ramp * rd[k] * torch.ones(B)
        e = q_ref - q
        e_int = torch.clamp(e_int + e * A.DT_CTRL, -0.05, 0.05)
        qdd_ref = torch.zeros(B) if qd_ref_prev is None else (qd_ref - qd_ref_prev) / A.DT_CTRL
        qd_ref_prev = qd_ref
        obs = torch.stack([e, qd_ref - qd_est, e_int, qd_est, q_ref, qd_ref, qdd_ref, tau_prev], -1)
        if policy_name == "pd":
            tau = torch.zeros(B)
        elif policy_name == "model_ff":
            tau = T.model_ff(obs)
        else:
            tau = T.policy(obs, theta)
        tau = tau * ramp
        tau_prev = tau
        pipe_q = [q_ref] + pipe_q[:-1]; pipe_f = [tau] + pipe_f[:-1]
        cq = torch.stack(pipe_q, -1).gather(1, sel).squeeze(1)
        cf = torch.stack(pipe_f, -1).gather(1, sel).squeeze(1)
        s = (q, qd_true, tau_m)
        for _ in range(A.SUBSTEPS):
            s = A.firmware_substep(s, cq, cf, p, T.KP, T.KD, xp=torch)
        q, qd_true, tau_m = s
        qd_est = 0.7 * qd_est + 0.3 * (q - q_prev) / A.DT_CTRL
        q_prev = q
        if t >= 1.0:
            errs.append(q_ref - q)
    E = torch.stack(errs)
    rms = 1e3 * E.pow(2).mean(0).sqrt()
    mx = 1e3 * E.abs().max(0).values
    pct = lambda x: [round(float(v), 3) for v in torch.quantile(x, torch.tensor([0.1, 0.5, 0.9]))]
    return {"rms_p10_p50_p90": pct(rms), "max_p10_p50_p90": pct(mx)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="../../docs/results/scenario_predictions.json")
    ap.add_argument("--plants", type=int, default=200)
    a = ap.parse_args()
    vqc = torch.tensor(M.load_params("vqc_params.json"))
    mlp_fn, _ = T.make_mlp_policy([8])
    mlp = torch.tensor(json.load(open("runs/mlp_8_s0.json"))["theta"])
    out = {"plants": a.plants, "ranges": A.RANDOM, "firmware_pd": A.FIRMWARE_PD, "tests": {}}
    with torch.no_grad():
        for name, kind, amp, freq, sec in TESTS:
            res = {}
            for pol, th in (("pd", None), ("model_ff", None), ("vqc", vqc), ("mlp", mlp)):
                if pol == "mlp":
                    saved = T.policy; T.policy = mlp_fn
                res[pol] = run("policy" if pol in ("vqc", "mlp") else pol, th, kind, amp, freq, sec, a.plants, seed=11)
                if pol == "mlp":
                    T.policy = saved
            out["tests"][name] = {"traj": kind, "amp": amp, "freq": freq, "seconds": sec, **res}
            print(name, {k: v["rms_p10_p50_p90"] for k, v in res.items()}, flush=True)
    json.dump(out, open(a.out, "w"), indent=1)
    print("saved", a.out)


if __name__ == "__main__":
    main()
