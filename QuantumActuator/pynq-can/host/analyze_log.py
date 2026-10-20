"""Summarize / plot run_controller.py CSV logs (works on the PC or the board).

    python analyze_log.py pd.csv vqc.csv [--plot out.png]
"""
import argparse
import csv
import math


def load(path):
    with open(path) as f:
        rows = list(csv.DictReader(f))
    return {k: [float(r[k]) for r in rows] for k in rows[0]}


def summary(d, skip_s=1.0):
    idx = [i for i, t in enumerate(d["t"]) if t >= skip_s] or list(range(len(d["t"])))
    e = [d["q_ref"][i] - d["q"][i] for i in idx]
    tau = [d["tau_ff"][i] for i in idx]
    dtau = [tau[i] - tau[i - 1] for i in range(1, len(tau))]
    rms = lambda xs: math.sqrt(sum(x * x for x in xs) / max(1, len(xs)))
    return dict(n=len(idx), rms_mrad=1e3 * rms(e), max_mrad=1e3 * max(map(abs, e)),
                tau_ff_rms=rms(tau), dtau_rms=rms(dtau), tau_meas_rms=rms([d["tau_meas"][i] for i in idx]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--plot", default=None)
    a = ap.parse_args()
    data = {p: load(p) for p in a.logs}
    for p, d in data.items():
        s = summary(d)
        print(f"{p}: " + "  ".join(f"{k}={v:.4g}" for k, v in s.items()))
    if a.plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(3, 1, sharex=True, figsize=(9, 7))
        first = next(iter(data.values()))
        ax[0].plot(first["t"], first["q_ref"], "k--", lw=1, label="q_ref")
        for p, d in data.items():
            ax[0].plot(d["t"], d["q"], lw=1, label=p)
            ax[1].plot(d["t"], [1e3 * (r - q) for r, q in zip(d["q_ref"], d["q"])], lw=1, label=p)
            ax[2].plot(d["t"], d["tau_ff"], lw=1, label=p)
        for a_, lab in zip(ax, ("position [rad]", "error [mrad]", "tau_ff [N·m]")):
            a_.set_ylabel(lab)
            a_.grid(alpha=0.3)
            a_.legend(fontsize=8)
        ax[2].set_xlabel("t [s]")
        fig.tight_layout()
        fig.savefig(a.plot, dpi=120)
        print("plot:", a.plot)


if __name__ == "__main__":
    main()
