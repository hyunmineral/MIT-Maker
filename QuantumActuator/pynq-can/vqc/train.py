"""Train the residual VQC feed-forward policy in simulation.

Plant + firmware loop: actuator_sim (Recoil MODE_POSITION PD at 2 kHz, EMA, clamp).
Policy: tau_ff = VQC(obs) sent with q_ref in RPDO3 at 1 kHz.

Stage 1  behaviour cloning of a nominal-model feed-forward (good initialization)
Stage 2  closed-loop back-propagation through time with domain randomization
         (inertia, friction, efficiency, 0-2 ms delay).

Baselines reported by evaluate():  pd (tau_ff = 0), model_ff (nominal-model
feed-forward), vqc.

    python train.py --out vqc_params.json
"""
from __future__ import annotations

import argparse
import math
import time

import torch

import actuator_sim as A
import vqc_model as M

torch.set_num_threads(8)
policy, _ = M.torch_policy()
N_PARAMS = M.N_PARAMS


def make_mlp_policy(hidden):
    """Classical baseline with the same encoded inputs and output squashing as the VQC."""
    sizes = [M.N_QUBITS] + list(hidden) + [1]
    shapes = [(sizes[i + 1], sizes[i]) for i in range(len(sizes) - 1)]
    n = sum(o * i + o for o, i in shapes)
    scale = torch.as_tensor(M.FEAT_SCALE)

    def mlp(obs, theta):
        h = math.pi * torch.tanh(scale * obs[:, list(M.FEAT_INDEX)])
        k = 0
        for j, (o, i) in enumerate(shapes):
            W = theta[k:k + o * i].reshape(o, i); k += o * i
            b = theta[k:k + o]; k += o
            h = h @ W.T + b
            if j < len(shapes) - 1:
                h = torch.tanh(h)
        return M.TAU_MAX * torch.tanh(M.OUT_GAIN * h[:, 0])
    return mlp, n
KP, KD = A.FIRMWARE_PD["kp"], A.FIRMWARE_PD["kd"]


def model_ff(obs):
    """Nominal inverse-dynamics feed-forward (the classical baseline / BC teacher)."""
    n = A.NOMINAL
    qd_ref, qdd_ref = obs[:, 5], obs[:, 6]
    tau_out = n["J"] * qdd_ref + n["b"] * qd_ref + n["tau_c"] * torch.tanh(qd_ref / 0.05)
    return torch.clamp(KD * qd_ref + tau_out / (A.GEAR * n["eta"]), -M.TAU_MAX, M.TAU_MAX)


def sample_params(B, gen, nominal=False):
    p = {}
    for k in ("J", "b", "tau_c", "eta"):
        lo, hi = A.RANDOM[k]
        p[k] = torch.full((B,), float(A.NOMINAL[k])) if nominal else lo + (hi - lo) * torch.rand(B, generator=gen)
    p["delay"] = (torch.full((B,), A.NOMINAL["delay"]) if nominal
                  else torch.randint(0, A.RANDOM["delay"][1] + 1, (B,), generator=gen)).long()
    return p


def sample_reference(B, T, gen):
    """Smooth random references: sum of two sines, amplitude 0.05-0.5 rad, 0.2-1.5 Hz."""
    t = torch.arange(T + 1) * A.DT_CTRL
    q = torch.zeros(T + 1, B)
    qd = torch.zeros(T + 1, B)
    for _ in range(2):
        amp = 0.025 + 0.225 * torch.rand(B, generator=gen)
        w = 2 * math.pi * (0.2 + 1.3 * torch.rand(B, generator=gen))
        ph = 2 * math.pi * torch.rand(B, generator=gen)
        q = q + amp * torch.sin(w * t[:, None] + ph)
        qd = qd + amp * w * torch.cos(w * t[:, None] + ph)
    return q, qd


def rollout(theta, T, B, gen, mode="vqc", nominal=False, keep_obs=False, tbptt=0):
    """mode: 'vqc' | 'pd' | 'model_ff'. tbptt>0 detaches the state every tbptt steps."""
    p = sample_params(B, gen, nominal)
    q_ref, qd_ref = sample_reference(B, T, gen)
    q = q_ref[0] + 0.02 * torch.randn(B, generator=gen)
    qd = torch.zeros(B)
    tau_m = torch.zeros(B)
    e_int = torch.zeros(B)
    tau_prev = torch.zeros(B)
    pipe_q = [q.clone() for _ in range(3)]
    pipe_f = [torch.zeros(B) for _ in range(3)]
    sel = p["delay"][:, None]
    obs_log, err, eff, dtau = [], [], [], []
    for k in range(T):
        if tbptt and k % tbptt == 0:
            q, qd, tau_m, e_int, tau_prev = (x.detach() for x in (q, qd, tau_m, e_int, tau_prev))
            pipe_f = [x.detach() for x in pipe_f]
        e = q_ref[k] - q
        e_int = torch.clamp(e_int + e * A.DT_CTRL, -0.05, 0.05)
        qdd_ref = (qd_ref[k] - qd_ref[k - 1]) / A.DT_CTRL if k else torch.zeros(B)
        obs = torch.stack([e, qd_ref[k] - qd, e_int, qd, q_ref[k], qd_ref[k], qdd_ref, tau_prev], -1)
        if mode == "pd":
            tau = torch.zeros(B)
        elif mode == "model_ff":
            tau = model_ff(obs)
        else:
            tau = policy(obs, theta)
        if keep_obs:
            obs_log.append(obs.detach())
        pipe_q = [q_ref[k]] + pipe_q[:-1]
        pipe_f = [tau] + pipe_f[:-1]
        cq = torch.stack(pipe_q, -1).gather(1, sel).squeeze(1)
        cf = torch.stack(pipe_f, -1).gather(1, sel).squeeze(1)
        s = (q, qd, tau_m)
        for _ in range(A.SUBSTEPS):
            s = A.firmware_substep(s, cq, cf, p, KP, KD, xp=torch)
        q, qd, tau_m = s
        err.append(e)
        eff.append(tau)
        dtau.append(tau - tau_prev)
        tau_prev = tau
    return dict(err=torch.stack(err), tau=torch.stack(eff), dtau=torch.stack(dtau),
                obs=torch.cat(obs_log) if keep_obs else None)


def evaluate(theta, seed=123, B=256, T=3000, modes=("pd", "model_ff", "vqc"), nominal=False):
    out = {}
    with torch.no_grad():
        for mode in modes:
            r = rollout(theta, T, B, torch.Generator().manual_seed(seed), mode=mode, nominal=nominal)
            e = r["err"][500:]
            out[mode] = dict(rms_mrad=round(1e3 * e.pow(2).mean().sqrt().item(), 3),
                             max_mrad=round(1e3 * e.abs().max().item(), 2),
                             dtau_rms=round(r["dtau"][500:].pow(2).mean().sqrt().item(), 5))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="vqc_params.json")
    ap.add_argument("--bc-epochs", type=int, default=600)
    ap.add_argument("--bptt-iters", type=int, default=200)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--model", choices=("vqc", "mlp"), default="vqc")
    ap.add_argument("--hidden", default="8", help="MLP hidden sizes, e.g. 8 or 64,64")
    args = ap.parse_args()

    global policy, N_PARAMS
    if args.model == "mlp":
        policy, N_PARAMS = make_mlp_policy([int(h) for h in args.hidden.split(",")])
        print(f"MLP hidden={args.hidden} params={N_PARAMS}", flush=True)
    gen = torch.Generator().manual_seed(args.seed)
    theta = (0.1 * torch.randn(N_PARAMS, generator=gen)).requires_grad_()
    t0 = time.time()

    # ---- Stage 1: BC on model feed-forward, states from model_ff closed loop
    with torch.no_grad():
        X = rollout(None, 2000, 128, gen, mode="model_ff", keep_obs=True)["obs"]
    Y = model_ff(X)
    opt = torch.optim.Adam([theta], lr=0.03)
    for ep in range(args.bc_epochs):
        idx = torch.randint(0, len(X), (4096,), generator=gen)
        loss = (policy(X[idx], theta) - Y[idx]).pow(2).mean()
        opt.zero_grad(); loss.backward(); opt.step()
        if ep % 100 == 0:
            print(f"[BC {ep}] mse={loss.item():.6f} (label var {Y.var().item():.5f})  {time.time()-t0:.0f}s", flush=True)
    print("after BC:", evaluate(theta.detach(), B=128, T=2000), flush=True)

    # ---- Stage 2: closed-loop BPTT with domain randomization
    opt = torch.optim.Adam([theta], lr=0.01)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, args.bptt_iters)
    best, best_theta = float("inf"), theta.detach().clone()
    for it in range(args.bptt_iters):
        r = rollout(theta, 600, 96, gen, mode="vqc", tbptt=100)
        e = r["err"][100:]
        loss = (e / 0.01).pow(2).mean() + (r["dtau"] / 0.01).pow(2).mean() * 0.1
        opt.zero_grad(); loss.backward()
        if torch.isfinite(theta.grad).all():
            torch.nn.utils.clip_grad_norm_([theta], 1.0)
            opt.step()
        else:
            print(f"[BPTT {it}] non-finite gradient, step skipped", flush=True)
        sched.step()
        if it % 10 == 0 or it == args.bptt_iters - 1:
            ev = evaluate(theta.detach(), B=128, T=2000, modes=("vqc",))["vqc"]
            if ev["rms_mrad"] < best:
                best, best_theta = ev["rms_mrad"], theta.detach().clone()
            print(f"[BPTT {it}] loss={loss.item():.3f} eval={ev}  {time.time()-t0:.0f}s", flush=True)

    final = {"randomized": evaluate(best_theta), "nominal": evaluate(best_theta, nominal=True)}
    print("final:", final)
    M.save_params(args.out, best_theta.numpy(), meta={"eval": final, "seed": args.seed, "firmware_pd": A.FIRMWARE_PD,
                                                      "nominal": A.NOMINAL, "randomization": A.RANDOM,
                                                      "model": args.model, "hidden": args.hidden,
                                                      "n_params": N_PARAMS})
    print("saved", args.out)


if __name__ == "__main__":
    main()
