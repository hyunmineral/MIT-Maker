"""Single-joint actuator model: MAD 5010 110KV + 15:1 cycloidal + Recoil position loop.

Units follow the firmware: position/velocity at the output shaft [rad, rad/s],
torque = firmware torque units (motor side, N*m, clamped to torque_limit = 1).

Control architecture (residual): the host sends RPDO3 [q_ref, tau_ff] at 1 kHz,
the firmware (MODE_POSITION, position_controller.c) runs at 2 kHz:

    tau  = kp*(q_ref - q) + kd*(0 - qd) + tau_ff          (no velocity target!)
    tau_m = clamp(EMA(alpha) of tau, +-torque_limit)
    J * qdd = G*eta*tau_m - b*qd - tau_c*tanh(qd/0.05)

The VQC supplies tau_ff (feed-forward / residual). The 0-2 ms command delay
models CAN + host jitter. Nominal values are estimates for a bench joint with
a small arm; training randomizes them (RANDOM).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

GEAR = 15.0
DT_CTRL = 1e-3          # host policy rate 1 kHz
SUBSTEPS = 2            # firmware position loop / EMA at 2 kHz
EMA_ALPHA = 0.27        # torque_filter_alpha (motor_configuration.json)
TORQUE_LIMIT = 1.0
QD_LIMIT = 18.0         # ~ 110 KV * 24 V / 15 at the output [rad/s]

FIRMWARE_PD = dict(kp=20.0, kd=0.15)       # written to the controller via SDO at start-up
NOMINAL = dict(J=0.014, b=0.05, tau_c=0.20, eta=0.85, delay=1)
RANDOM = dict(J=(0.007, 0.028), b=(0.02, 0.10), tau_c=(0.05, 0.40), eta=(0.75, 0.92), delay=(0, 2))


def clamp(x, lo, hi, xp=math):
    return max(lo, min(hi, x)) if xp is math else xp.clamp(x, lo, hi)


def tanh(x, xp=math):
    return math.tanh(x) if xp is math else xp.tanh(x)


def firmware_substep(state, cmd_q, cmd_ff, p, kp, kd, xp=math):
    """One 2 kHz firmware position-loop tick plus plant integration (works for floats and tensors)."""
    q, qd, tau_m = state
    tau = kp * (cmd_q - q) - kd * qd + cmd_ff
    tau_m = clamp(tau_m + EMA_ALPHA * (tau - tau_m), -TORQUE_LIMIT, TORQUE_LIMIT, xp)
    qdd = (GEAR * p["eta"] * tau_m - p["b"] * qd - p["tau_c"] * tanh(qd / 0.05, xp)) / p["J"]
    h = DT_CTRL / SUBSTEPS
    qd = clamp(qd + qdd * h, -QD_LIMIT, QD_LIMIT, xp)
    return q + qd * h, qd, tau_m


@dataclass
class Joint:
    """Scalar simulator (virtual Recoil device and evaluation)."""
    J: float = NOMINAL["J"]
    b: float = NOMINAL["b"]
    tau_c: float = NOMINAL["tau_c"]
    eta: float = NOMINAL["eta"]
    delay: int = NOMINAL["delay"]
    kp: float = FIRMWARE_PD["kp"]
    kd: float = FIRMWARE_PD["kd"]
    q: float = 0.0
    qd: float = 0.0
    tau_m: float = 0.0
    pipe: list = field(default_factory=list)

    def step(self, q_ref: float, tau_ff: float) -> None:
        """Advance one 1 kHz host period with RPDO3 command (q_ref, tau_ff)."""
        self.pipe.append((q_ref, tau_ff))
        cmd = self.pipe.pop(0) if len(self.pipe) > self.delay else (self.q, 0.0)
        p = dict(J=self.J, b=self.b, tau_c=self.tau_c, eta=self.eta)
        s = (self.q, self.qd, self.tau_m)
        for _ in range(SUBSTEPS):
            s = firmware_substep(s, cmd[0], cmd[1], p, self.kp, self.kd)
        self.q, self.qd, self.tau_m = s


class ObsBuilder:
    """8-dim observation: [pos_err, vel_err, pos_err_int, qd, q_ref, qd_ref, qdd_ref, tau_ff_prev]."""

    def __init__(self, int_limit: float = 0.05):
        self.e_int = 0.0
        self.tau_prev = 0.0
        self.qd_ref_prev = None
        self.int_limit = int_limit

    def __call__(self, q, qd, q_ref, qd_ref):
        e = q_ref - q
        self.e_int = clamp(self.e_int + e * DT_CTRL, -self.int_limit, self.int_limit)
        qdd_ref = 0.0 if self.qd_ref_prev is None else (qd_ref - self.qd_ref_prev) / DT_CTRL
        self.qd_ref_prev = qd_ref
        return [e, qd_ref - qd, self.e_int, qd, q_ref, qd_ref, qdd_ref, self.tau_prev]

    def commit(self, tau):
        self.tau_prev = tau


def reference(t: float, kind: str = "sine", amp: float = 0.5, freq: float = 0.5):
    """(q_ref, qd_ref) evaluation trajectories."""
    w = 2 * math.pi * freq
    if kind == "sine":
        return amp * math.sin(w * t), amp * w * math.cos(w * t)
    if kind == "step":
        return (amp if (t % (1 / freq)) < 0.5 / freq else -amp), 0.0
    if kind == "chirp":   # 0.5 -> ~3 Hz over 5 s
        f0, k = freq, 0.5
        ph = 2 * math.pi * (f0 * t + 0.5 * k * t * t)
        return amp * math.sin(ph), amp * 2 * math.pi * (f0 + k * t) * math.cos(ph)
    raise ValueError(kind)


def model_ff(obs, kd=FIRMWARE_PD["kd"], tau_max=0.8):
    """Nominal inverse-dynamics feed-forward (classical baseline), scalar version."""
    n = NOMINAL
    qd_ref, qdd_ref = obs[5], obs[6]
    tau_out = n["J"] * qdd_ref + n["b"] * qd_ref + n["tau_c"] * math.tanh(qd_ref / 0.05)
    return clamp(kd * qd_ref + tau_out / (GEAR * n["eta"]), -tau_max, tau_max)
