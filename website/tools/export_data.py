"""Export the trained policies, plant model and measured results for the website.

    python website/tools/export_data.py
Writes website/data/policies.json, website/data/results.json and
website/data/reference.json (Python reference outputs used by the JS self-test).
"""
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VQC_DIR = os.path.join(ROOT, "pynq-can", "vqc")
OUT = os.path.join(ROOT, "website", "data")
sys.path.insert(0, VQC_DIR)

import actuator_sim as A  # noqa: E402
import vqc_model as M  # noqa: E402


def load(name):
    with open(os.path.join(VQC_DIR, name)) as f:
        return json.load(f)


def main():
    vqc = load("vqc_params.json")
    mlp = load(os.path.join("runs", "mlp_8_s0.json"))
    policies = {
        "vqc": {"theta": vqc["theta"], "n_qubits": M.N_QUBITS, "n_layers": M.N_LAYERS,
                "perm": [int(v) for v in M.PERM]},
        "mlp": {"theta": mlp["theta"], "sizes": [M.N_QUBITS, 8, 1]},
        "encoding": {"feat_index": list(M.FEAT_INDEX), "feat_scale": [float(v) for v in M.FEAT_SCALE],
                     "features": list(M.FEATURES), "tau_max": M.TAU_MAX, "out_gain": M.OUT_GAIN},
        "plant": {"gear": A.GEAR, "dt": A.DT_CTRL, "substeps": A.SUBSTEPS, "ema_alpha": A.EMA_ALPHA,
                  "torque_limit": A.TORQUE_LIMIT, "qd_limit": A.QD_LIMIT, "firmware_pd": A.FIRMWARE_PD,
                  "nominal": A.NOMINAL, "random": A.RANDOM},
    }
    os.makedirs(OUT, exist_ok=True)
    json.dump(policies, open(os.path.join(OUT, "policies.json"), "w"), indent=0)

    # Reference outputs for the browser self-test: policy values and a short closed loop.
    rng = np.random.default_rng(3)
    obs = rng.normal(0, 1, (20, 8)) * np.array([0.01, 0.2, 0.02, 1.0, 0.3, 1.0, 10.0, 0.3])
    import torch
    from train import make_mlp_policy
    mlp_fn, _ = make_mlp_policy([8])
    ref = {
        "obs": obs.tolist(),
        "vqc_tau": [M.policy_numpy(o, np.asarray(vqc["theta"])) for o in obs],
        "mlp_tau": mlp_fn(torch.tensor(obs, dtype=torch.float32), torch.tensor(mlp["theta"])).tolist(),
        "model_ff": [A.model_ff(list(o)) for o in obs],
    }
    # closed loop: run_controller-style sine with 1 s ramp, nominal joint, each policy
    from vqc_runtime import VQCPolicy
    pol_vqc = VQCPolicy(vqc["theta"], use_c=False)
    loops = {}
    for name in ("pd", "model_ff", "vqc", "mlp"):
        j = A.Joint()
        ob = A.ObsBuilder()
        errs, q, qd, q_prev = [], 0.0, 0.0, 0.0
        for k in range(4000):
            t = k * A.DT_CTRL
            ramp = min(1.0, t)
            r, rd = A.reference(t, "sine", 0.3, 0.5)
            q_ref, qd_ref = ramp * r, ramp * rd
            o = ob(q, qd, q_ref, qd_ref)
            if name == "pd":
                tau = 0.0
            elif name == "model_ff":
                tau = A.model_ff(o)
            elif name == "vqc":
                tau = pol_vqc(o)
            else:
                tau = float(mlp_fn(torch.tensor([o], dtype=torch.float32), torch.tensor(mlp["theta"]))[0])
            tau *= ramp
            ob.commit(tau)
            j.step(q_ref, tau)
            q = j.q
            qd = 0.7 * qd + 0.3 * (q - q_prev) / A.DT_CTRL
            q_prev = q
            errs.append(q_ref - q)
        e = np.array(errs[1000:])
        loops[name] = {"rms_mrad": float(1e3 * np.sqrt((e ** 2).mean())), "q_final": q}
    ref["loops"] = loops
    json.dump(ref, open(os.path.join(OUT, "reference.json"), "w"))
    res = json.load(open(os.path.join(ROOT, "docs", "results", "results.json"), encoding="utf-8"))
    json.dump(res, open(os.path.join(OUT, "results.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("loops:", {k: round(v["rms_mrad"], 3) for k, v in loops.items()})


if __name__ == "__main__":
    main()
