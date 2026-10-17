"""VQC policy with the state-vector core on the PL (HLS vqc_top on AXI4-Lite);
same call interface as vqc_runtime.VQCPolicy:

    pol = VQCPolicyPL("vqc_can0.bit", "vqc_params.json")
    tau_ff = pol(obs8)

Split of work: the PS computes the 6 encoding angles and their half-angle
cos/sin (12 floats) and the output squashing tau = tau_max*tanh(g*z); the PL
runs the 64-amplitude simulation (24 fused gates + 4 CNOT rings) and returns
z = <Z0>. Register offsets come from the HLS-generated xvqc_top_hw.h placed
next to the bitstream (build_can0_overlay.tcl copies it to vivado/out/).
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "vqc"))

import vqc_model as M  # noqa: E402
from vqc_runtime import fused_weights  # noqa: E402

AP_START, AP_DONE = 0x1, 0x2


def read_offsets(header_path: str) -> dict:
    regs = {}
    with open(header_path) as f:
        for m in re.finditer(r"#define\s+XVQC_TOP_CTRL_ADDR_(\w+)\s+0x([0-9a-fA-F]+)", f.read()):
            regs[m.group(1)] = int(m.group(2), 16)
    return regs


class VQCPolicyPL:
    backend = "pl"

    def __init__(self, bitfile: str, params_path: str, header: str | None = None, download: bool = True):
        from pynq import Overlay
        self.ol = Overlay(bitfile, download=download)
        regs = read_offsets(header or os.path.join(os.path.dirname(os.path.abspath(bitfile)), "xvqc_top_hw.h"))
        self.mem = self.ol.vqc_top_0.mmio.array            # uint32 view of the register space
        self.o_ctrl = regs["AP_CTRL"] // 4
        self.o_cs = regs["CS_BASE"] // 4
        self.o_z = regs["Z_DATA"] // 4

        with open(params_path) as f:
            d = json.load(f)
        W = fused_weights(d["theta"])
        o_w = regs["W_BASE"] // 4
        self.mem[o_w:o_w + W.size] = np.asarray(W, dtype=np.float32).view(np.uint32)
        self.feat_index = list(d.get("feat_index", M.FEAT_INDEX))
        self.feat_scale = [float(v) for v in d.get("feat_scale", M.FEAT_SCALE)]
        self.tau_max = float(d.get("tau_max", M.TAU_MAX))
        self.out_gain = float(d.get("out_gain", M.OUT_GAIN))
        self._cs = np.zeros(2 * M.N_QUBITS, dtype=np.float32)
        self.last_core_us = 0.0

        # Fast path: one ctypes call into libvqc.so (vqc_pl_driver.c) does the
        # pre/post-processing and register traffic; Python MMIO is the fallback.
        self.fast = None
        try:
            import ctypes
            from vqc_runtime import VQCPolicy, _Config
            ref = VQCPolicy(d["theta"], self.feat_index, self.feat_scale, self.tau_max, self.out_gain)
            lib = ref.lib
            if lib is not None:
                for fn in ("vqc_pl_open", "vqc_pl_load_w"):
                    getattr(lib, fn).restype = ctypes.c_int if fn == "vqc_pl_open" else None
                lib.vqc_pl_open.argtypes = [ctypes.c_uint32] * 4
                lib.vqc_pl_policy.restype = ctypes.c_float
                lib.vqc_pl_policy.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.POINTER(_Config)]
                lib.vqc_pl_load_w.argtypes = [ctypes.POINTER(ctypes.c_float)]
                base = self.ol.vqc_top_0.mmio.base_addr
                if lib.vqc_pl_open(base, regs["CS_BASE"], regs["W_BASE"], regs["Z_DATA"]) == 0:
                    lib.vqc_pl_load_w(ref.cfg.W)
                    self.fast, self._ref = lib, ref
                    self.backend = "pl[c]"
        except (OSError, AttributeError):
            self.fast = None

    def expval(self, obs, timeout: float = 1e-3) -> float:
        cs = self._cs
        for q in range(M.N_QUBITS):
            x = math.pi * math.tanh(self.feat_scale[q] * obs[self.feat_index[q]])
            cs[2 * q] = math.cos(0.5 * x)
            cs[2 * q + 1] = math.sin(0.5 * x)
        self.mem[self.o_cs:self.o_cs + cs.size] = cs.view(np.uint32)
        t0 = time.perf_counter()
        self.mem[self.o_ctrl] = AP_START
        while not (self.mem[self.o_ctrl] & AP_DONE):
            if time.perf_counter() - t0 > timeout:
                raise TimeoutError("vqc_top did not finish")
        self.last_core_us = (time.perf_counter() - t0) * 1e6
        return float(np.uint32(self.mem[self.o_z]).view(np.float32))

    def __call__(self, obs) -> float:
        if self.fast is not None:
            o = self._ref._obs
            for i in range(8):
                o[i] = obs[i]
            return self.fast.vqc_pl_policy(o, self._ref._cfg_ref)
        return self.tau_max * math.tanh(self.out_gain * self.expval(obs))


if __name__ == "__main__":
    # Compare the PL core with the C kernel on the exported test vectors and time it.
    import argparse
    from vqc_runtime import VQCPolicy
    ap = argparse.ArgumentParser()
    ap.add_argument("bitfile")
    ap.add_argument("params")
    a = ap.parse_args()
    pl = VQCPolicyPL(a.bitfile, a.params)
    ref = VQCPolicy.from_json(a.params)
    d = np.load(os.path.join(HERE, "..", "vqc", "test_vectors.npz"))
    if not np.allclose(d["theta"], ref.theta):
        print("note: test_vectors.npz was exported for different parameters; comparing PL vs C kernel only")
    err = max(abs(pl(o) - ref(o)) for o in d["obs"])
    rng = np.random.default_rng(1)
    obs_r = rng.normal(0, 0.3, (500, 8)).astype(np.float32)
    err_r = max(abs(pl(o) - ref(o)) for o in obs_r)
    tot = []
    for o in obs_r:
        t = time.perf_counter(); pl(o); tot.append((time.perf_counter() - t) * 1e6)
    tot.sort()
    print(f"PL vs C kernel: max err {err:.2e} (test vectors), {err_r:.2e} (500 random obs)")
    print(f"backend {pl.backend}: full call p50 {tot[250]:.1f} us  p99 {tot[495]:.1f} us")
    fast, pl.fast = pl.fast, None                      # python-MMIO path for comparison
    t2 = []
    for o in obs_r[:200]:
        t = time.perf_counter(); pl(o); t2.append((time.perf_counter() - t) * 1e6)
    t2.sort(); pl.fast = fast
    print(f"python-MMIO path: full call p50 {t2[100]:.1f} us; core start->done p50 {sorted([pl.last_core_us])[0]:.1f} us")
