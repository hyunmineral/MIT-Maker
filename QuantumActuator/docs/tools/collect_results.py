"""Collect the measured results into docs/results/results.json and fill the
⟪…⟫ placeholders in the docs/*.md files.

    python docs/tools/collect_results.py

Training metrics are read from pynq-can/vqc/{vqc_params.json, runs/*.json}.
Hardware measurements (PYNQ-Z2, 2026-10-05/06) are recorded below as constants,
each with the command that produced it (see actuator-vqc-control-report.md).
"""
import glob
import json
import os
import re
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
VQC = os.path.join(os.path.dirname(DOCS), "pynq-can", "vqc")


def load_runs():
    runs = {"vqc": [], "mlp_8": [], "mlp_64x64": []}
    files = [os.path.join(VQC, "vqc_params.json")] + sorted(glob.glob(os.path.join(VQC, "runs", "*.json")))
    for f in files:
        meta = json.load(open(f))["meta"]
        key = "vqc" if meta.get("model", "vqc") == "vqc" else "mlp_" + meta["hidden"].replace(",", "x")
        ev = meta["eval"]
        runs[key].append(dict(file=os.path.relpath(f, VQC), seed=meta["seed"], n_params=meta.get("n_params", 72),
                              rand=ev["randomized"]["vqc"], nom=ev["nominal"]["vqc"]))
    base = json.load(open(files[0]))["meta"]["eval"]
    return runs, base


def agg(rs, key, field):
    v = [r[key][field] for r in rs]
    return round(st.mean(v), 3), round(st.stdev(v), 3) if len(v) > 1 else 0.0


def main():
    runs, base = load_runs()
    R = {"generated": "2026-10-06", "training_runs": runs}

    vr, vr_s = agg(runs["vqc"], "rand", "rms_mrad")
    vn, vn_s = agg(runs["vqc"], "nom", "rms_mrad")
    vm, _ = agg(runs["vqc"], "rand", "max_mrad")
    m8, m8_s = agg(runs["mlp_8"], "rand", "rms_mrad")
    m8n, m8n_s = agg(runs["mlp_8"], "nom", "rms_mrad")
    m64, m64_s = agg(runs["mlp_64x64"], "rand", "rms_mrad")
    m64n, m64n_s = agg(runs["mlp_64x64"], "nom", "rms_mrad")
    R["policy_comparison"] = [
        dict(label="PD only", color="pd", rms_mean=base["randomized"]["pd"]["rms_mrad"], nom=base["nominal"]["pd"]["rms_mrad"]),
        dict(label="PD+model FF", color="model_ff", rms_mean=base["randomized"]["model_ff"]["rms_mrad"],
             nom=base["nominal"]["model_ff"]["rms_mrad"]),
        dict(label="PD+VQC\n(72)", color="vqc", params=72, rms_mean=vr, rms_std=vr_s, nom=vn, nom_std=vn_s),
        dict(label="PD+MLP 6-8-1\n(65)", color="mlp_s", params=runs["mlp_8"][0]["n_params"], rms_mean=m8, rms_std=m8_s,
             nom=m8n, nom_std=m8n_s),
        dict(label="PD+MLP 6-64-64-1\n(4,673)", color="mlp_l", params=runs["mlp_64x64"][0]["n_params"], rms_mean=m64,
             rms_std=m64_s, nom=m64n, nom_std=m64n_s),
    ]
    R["hls_iterations"] = [
        dict(label="v1 baseline", latency_us=153.4, cycles=15343, clock_ns=14.5,
             timing_met=False, lut_pct=36, dsp_pct=40),
        dict(label="v2 full partition\n+unroll", latency_us=124.6, cycles=12462, clock_ns=19.9, timing_met=False, lut_pct=74, dsp_pct=51),
        dict(label="v3 flatten off", latency_us=129.2, cycles=12915, clock_ns=14.5, timing_met=False, lut_pct=61, dsp_pct=62),
        dict(label="v4 ping-pong", latency_us=26.4, cycles=2643, clock_ns=8.84, timing_met=True, lut_pct=66, dsp_pct=66),
        dict(label="v5 transcend.→PS\n(final)", latency_us=22.5, cycles=2248, clock_ns=8.84, timing_met=True, lut_pct=40, dsp_pct=32),
    ]
    R["bitstream_vqc_can0"] = dict(wns_ns=0.366, whs_ns=0.020, lut=15404, lut_pct=28.95, ff=23392, ff_pct=21.98,
                                   dsp=72, dsp_pct=32.73, bram=2, bram_pct=1.43)
    R["timing_us"] = dict(
        kernel_ps_c=64.6, kernel_ps_c_p99=65.7,                 # bench_pl, pure C, SCHED_FIFO
        pl_path_c=29.0, pl_path_c_p99=29.8, pl_path_c_max=195.5,
        pl_vs_ps_max_abs_diff=0.0,
        policy_ps_python_p50=109.3, policy_pl_python_p50=99.2,   # one python call
        policy_pl_python_p99=114.5,
        pl_python_mmio_path_p50=745.7,
        hls_core_cycles=2248, hls_core_us=22.5, cosim_us_v4=26.37,
        can_pingpong_p50=482, can_pingpong_p99=644, can_pingpong_loss="32/3000",
        can_rtt_expected=385,        # 350-420 us estimate, see fix_rtt_estimate.py
        loop_jitter_sim_pl=dict(p50=1.2, p99=4.1, max=4.7),
        loop_jitter_sim_ps=dict(p50=1.8, p99=22.9, max=76.6),
        loop_jitter_can_pd_cpu_pinned=dict(p50=1.4, p99="24~44", max=811),
    )
    R["pynq_tracking"] = {
        "sim": {"pd": [6.01, 8.32], "model_ff": [0.17, 0.29], "vqc_ps": [1.21, 2.78], "vqc_pl": [1.21, 2.78]},
        "can_loopback": {"pd": [6.31, 10.18], "model_ff": [0.38, 1.34], "vqc_ps": [1.45, 3.34], "vqc_pl": [1.38, 3.47]},
    }
    R["numerics"] = {"pl_vs_c_test_vectors": 3.73e-7, "pl_vs_c_random500": 3.87e-7, "cosim_pass_err": 9.5e-7}
    os.makedirs(os.path.join(DOCS, "results"), exist_ok=True)
    json.dump(R, open(os.path.join(DOCS, "results", "results.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    t = R["timing_us"]
    fill = {
        "VQC_RAND": f"{vr:.2f} ± {vr_s:.2f}" if len(runs["vqc"]) > 1 else f"{vr:.2f}",
        "VQC_NOM": f"{vn:.2f} ± {vn_s:.2f}" if len(runs["vqc"]) > 1 else f"{vn:.2f}",
        "VQC_MAX": f"{vm:.1f}",
        "VQC_VS_MLP": f"{100 * (vr - m8) / vr:.0f}",
        "HLS5_LAT": "22.5", "HLS5_CYC": "2,248", "HLS5_CLK": "8.84", "HLS5_LUT": "40", "HLS5_DSP": "32",
        "BIT5_WNS": "+0.366", "BIT5_LUT": "15,404 (29.0 %)", "BIT5_FF": "23,392 (22.0 %)",
        "BIT5_DSP": "72 (32.7 %)", "BIT5_BRAM": "2 (1.4 %)", "BIT5_DSP_PCT": "33%",
        "PL_ERR": "3.9e-7 (bit-identical to PS on the C path)",
        "PL_SPEEDUP": f"{t['kernel_ps_c'] / t['pl_path_c']:.1f}",
        "PL_CORE_P50": "approx. 22.5 (HLS) / 26 (incl. polling)",
        "PL_CALL_P50": f"{t['pl_path_c']:.0f} (C) / {t['policy_pl_python_p50']:.0f} (Python)",
        "PL_CALL_P99": f"{t['pl_path_c_p99']:.1f} (C) / {t['policy_pl_python_p99']:.0f} (Python)",
        "PL_TRACK_SIM": "1.21 / 2.78 (same as PS)",
        "PL_TRACK_CAN": "1.38 / 3.47",
    }
    for name in ("actuator-vqc-control-report.md", "paper-vqc-actuator.md", "guide-for-beginners.md"):
        p = os.path.join(DOCS, name)
        s = open(p, encoding="utf-8").read()
        s2 = re.sub(r"⟪([A-Z0-9_]+)⟫", lambda m: fill.get(m.group(1), m.group(0)), s)
        left = re.findall(r"⟪([A-Z0-9_]+)⟫", s2)
        if s2 != s:
            open(p, "w", encoding="utf-8", newline="\n").write(s2)
        print(name, "unfilled:", sorted(set(left)) or "none")
    print(json.dumps({k: R[k] for k in ("policy_comparison",)}, ensure_ascii=False)[:600])


if __name__ == "__main__":
    main()
