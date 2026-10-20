"""6-qubit / 4-layer data-reuploading VQC policy (72 trainable angles).

Circuit per layer l (qubit q = 0..5, qubit 0 is the MSB of the basis index):
    RY(x_q) -> RX(theta[l,q,0]) -> RY(theta[l,q,1]) -> RZ(theta[l,q,2])
    then CNOT ring 0->1, 1->2, 2->3, 3->4, 4->5, 5->0
Output: <Z_0>  ->  tau_ff = TAU_MAX * tanh(OUT_GAIN * <Z_0>)
(residual feed-forward torque added by the firmware position loop, RPDO3)

The four single-qubit gates of a layer are fused into one 2x2 unitary per
qubit and the CNOT ring into one basis permutation; vqc_kernel.c implements
exactly the same arithmetic in float32 for the PS (ctypes) and for Vitis HLS.
"""
from __future__ import annotations

import json
import math

import numpy as np

N_QUBITS = 6
N_LAYERS = 4
DIM = 1 << N_QUBITS
N_PARAMS = N_LAYERS * N_QUBITS * 3

# Observation (8): pos_err, vel_err, pos_err_int, qd, q_ref, qd_ref, qdd_ref, tau_prev
# Encoded features (6): x_q = pi * tanh(FEAT_SCALE[q] * obs[FEAT_INDEX[q]])
# Feedback is the firmware PD's job: feeding tau_prev back into the circuit made
# the policy chatter (dtau_rms 0.03 vs 0.003 without), and high-gain error
# features hurt as well, so the encoding is reference-centric with only a
# low-gain position-error channel.
FEATURES = ("pos_err_int", "qd_ref", "qdd_ref", "qd", "q_ref", "pos_err")
FEAT_INDEX = (2, 5, 6, 3, 4, 0)
FEAT_SCALE = np.array([10.0, 0.25, 0.02, 0.25, 1.0, 2.0], dtype=np.float32)
TAU_MAX = 0.8      # residual feed-forward limit (firmware total torque_limit is 1.0)
OUT_GAIN = 2.0


def features_from_obs(obs: np.ndarray) -> np.ndarray:
    """obs[..., 8] -> encoding angles[..., 6]."""
    f = np.asarray(obs, dtype=np.float32)[..., list(FEAT_INDEX)]
    return (math.pi * np.tanh(FEAT_SCALE * f)).astype(np.float32)


def cnot_ring_permutation() -> np.ndarray:
    """new_state[i] = old_state[perm[i]] after CNOT(0,1)...CNOT(5,0)."""
    def bit(i, q):
        return (i >> (N_QUBITS - 1 - q)) & 1

    perm = np.arange(DIM)
    for c in range(N_QUBITS):
        t = (c + 1) % N_QUBITS
        mask = 1 << (N_QUBITS - 1 - t)
        perm = np.array([perm[i ^ mask] if bit(i, c) else perm[i] for i in range(DIM)])
    return perm


PERM = cnot_ring_permutation()
Z0_SIGN = np.array([1.0 if ((i >> (N_QUBITS - 1)) & 1) == 0 else -1.0 for i in range(DIM)], dtype=np.float32)


# ---------------------------------------------------------------- numpy ref
def _rx(a):
    c, s = math.cos(a / 2), math.sin(a / 2)
    return np.array([[c, -1j * s], [-1j * s, c]], dtype=np.complex64)


def _ry(a):
    c, s = math.cos(a / 2), math.sin(a / 2)
    return np.array([[c, -s], [s, c]], dtype=np.complex64)


def _rz(a):
    return np.array([[np.exp(-0.5j * a), 0], [0, np.exp(0.5j * a)]], dtype=np.complex64)


def expval_z0_numpy(x: np.ndarray, theta: np.ndarray) -> float:
    """Gate-by-gate reference (no fusion) for a single sample."""
    theta = np.asarray(theta, dtype=np.float64).reshape(N_LAYERS, N_QUBITS, 3)
    psi = np.zeros([2] * N_QUBITS, dtype=np.complex128)
    psi[(0,) * N_QUBITS] = 1.0
    for l in range(N_LAYERS):
        for q in range(N_QUBITS):
            u = _rz(theta[l, q, 2]) @ _ry(theta[l, q, 1]) @ _rx(theta[l, q, 0]) @ _ry(x[q])
            psi = np.moveaxis(np.tensordot(u, psi, axes=([1], [q])), 0, q)
        flat = psi.reshape(DIM)
        psi = flat[PERM].reshape([2] * N_QUBITS)
    p = np.abs(psi.reshape(DIM)) ** 2
    return float(np.dot(p, Z0_SIGN))


def policy_numpy(obs: np.ndarray, theta: np.ndarray) -> float:
    z = expval_z0_numpy(features_from_obs(obs), theta)
    return TAU_MAX * math.tanh(OUT_GAIN * z)


# ---------------------------------------------------------------- torch
def torch_policy():
    import torch

    perm = torch.as_tensor(PERM)
    z0 = torch.as_tensor(Z0_SIGN)

    def fused_unitaries(x, theta):
        """x[B,6], theta[L,6,3] -> per-layer fused U[B,L,6,2,2] (complex64)."""
        def rot(axis, a):
            c, s = torch.cos(a / 2).to(torch.complex64), torch.sin(a / 2).to(torch.complex64)
            one = torch.ones_like(c)
            zero = torch.zeros_like(c)
            if axis == "x":
                m = [c, -1j * s, -1j * s, c]
            elif axis == "y":
                m = [c, -s, s, c]
            else:
                e = torch.exp(-0.5j * a.to(torch.complex64))
                m = [e, zero, zero, torch.conj(e) * one]
            return torch.stack(m, -1).reshape(*a.shape, 2, 2)

        th = theta.unsqueeze(0)                                      # [1,L,6,3]
        ry_x = rot("y", x).unsqueeze(1)                              # [B,1,6,2,2]
        u = rot("z", th[..., 2]) @ rot("y", th[..., 1]) @ rot("x", th[..., 0])  # [1,L,6,2,2]
        return u @ ry_x                                              # [B,L,6,2,2]

    def expval(x, theta):
        B = x.shape[0]
        U = fused_unitaries(x, theta.reshape(N_LAYERS, N_QUBITS, 3))
        psi = torch.zeros(B, DIM, dtype=torch.complex64)
        psi[:, 0] = 1
        for l in range(N_LAYERS):
            psi = psi.reshape(B, *([2] * N_QUBITS))
            for q in range(N_QUBITS):
                psi = torch.movedim(torch.einsum("bij,bj...->bi...", U[:, l, q],
                                                 torch.movedim(psi, q + 1, 1)), 1, q + 1)
            psi = psi.reshape(B, DIM)[:, perm]
        return (psi.real ** 2 + psi.imag ** 2) @ z0

    def features(obs):
        f = obs[:, list(FEAT_INDEX)]
        return math.pi * torch.tanh(torch.as_tensor(FEAT_SCALE) * f)

    def policy(obs, theta):
        return TAU_MAX * torch.tanh(OUT_GAIN * expval(features(obs), theta))

    return policy, expval


# ---------------------------------------------------------------- export
def save_params(path: str, theta: np.ndarray, meta: dict | None = None) -> None:
    with open(path, "w") as f:
        json.dump({"theta": [float(v) for v in np.asarray(theta).ravel()],
                   "feat_index": list(FEAT_INDEX), "feat_scale": FEAT_SCALE.tolist(), "tau_max": TAU_MAX, "out_gain": OUT_GAIN,
                   "meta": meta or {}}, f, indent=1)


def load_params(path: str) -> np.ndarray:
    with open(path) as f:
        return np.asarray(json.load(f)["theta"], dtype=np.float32)
