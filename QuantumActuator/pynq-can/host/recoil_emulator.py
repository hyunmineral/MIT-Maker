"""Emulation of the Recoil firmware CAN handler (motor_controller.c) with an
optional simulated joint, used by the unit tests and by virtual_recoil.py.

Each RPDO2/RPDO3 advances the joint by one 1 ms host period, so the emulator
stays in lock-step with a 1 kHz host loop.
"""
from __future__ import annotations

import os
import struct
import sys
from collections import deque

import recoil as R

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vqc"))


class FakeRecoil:
    def __init__(self, device_id=1, joint=None, step_on_pdo=True):
        """step_on_pdo=True: each RPDO advances the joint 1 ms (lock-step, tests).
        False: the caller advances the joint with advance() on wall-clock time,
        like the real firmware whose loops run independently of CAN traffic."""
        self.mem = bytearray(0x200)
        self.device_id = device_id
        self.joint = joint
        self.step_on_pdo = step_on_pdo
        self.watchdog_kicks = 0
        self.u32(R.PARAM_DEVICE_ID, device_id)
        self.u32(R.PARAM_FIRMWARE_VERSION, 0x20250226)
        self.u32(R.PARAM_MODE, R.MODE_IDLE)
        self.f32(R.PARAM_GEAR_RATIO, 1.0)          # firmware default (position_controller.c), host sets -15
        self.f32(R.PARAM_TORQUE_LIMIT, 1.0)
        self.f32(R.PARAM_POSITION_KP, 50.0)
        self.f32(R.PARAM_VELOCITY_KP, 2.0)
        self.f32(R.PARAM_BUS_VOLTAGE_MEASURED, 24.0)
        self.f32(R.PARAM_POSITION_MEASURED, 0.25 if joint is None else joint.q)

    def u32(self, off, v=None):
        if v is None:
            return struct.unpack_from("<I", self.mem, off)[0]
        struct.pack_into("<I", self.mem, off, v)

    def f32(self, off, v=None):
        if v is None:
            return struct.unpack_from("<f", self.mem, off)[0]
        struct.pack_into("<f", self.mem, off, v)

    def advance(self, n_steps=1):
        """Real-time mode: integrate the joint n x 1 ms with the latest RPDO command."""
        for _ in range(n_steps):
            self._advance_joint(self.f32(R.PARAM_POSITION_TARGET), self.f32(R.PARAM_TORQUE_TARGET))

    def _advance_joint(self, q_ref, tau_ff):
        """Firmware units -> joint model. Like Recoil, positions are encoder/gear_ratio
        and torques are scaled by gear_ratio (i_q = T / Kt / gear). The joint model works
        in output-shaft radians and motor-side torque; the actuator reduction is 15:1, so
        firmware position = s * q_out with s = 15/|gear|, motor torque = T_fw / |gear|."""
        j = self.joint
        g = abs(self.f32(R.PARAM_GEAR_RATIO)) or 1.0
        s = 15.0 / g
        mode = self.u32(R.PARAM_MODE)
        if mode == R.MODE_POSITION:
            j.kp, j.kd = self.f32(R.PARAM_POSITION_KP) * s / g, self.f32(R.PARAM_VELOCITY_KP) * s / g
            j.step(q_ref / s, tau_ff / g)
        elif mode == R.MODE_DAMPING:
            j.kp, j.kd = 0.0, 0.1
            j.step(j.q, 0.0)
        else:
            j.kp, j.kd = 0.0, 0.0
            j.step(j.q, 0.0)
        self.f32(R.PARAM_POSITION_MEASURED, j.q * s)
        self.f32(R.PARAM_VELOCITY_MEASURED, j.qd * s)
        self.f32(R.PARAM_TORQUE_MEASURED, j.tau_m * g)

    def handle(self, can_id, data):
        """Returns (reply_id, reply_bytes) or None, like the firmware."""
        dev = can_id & 0x7F
        if dev and dev != self.device_id:
            return None
        func = can_id >> 7
        if func == R.FUNC_NMT:
            if data[1] == self.device_id:
                self.u32(R.PARAM_MODE, data[0])
        elif func == R.FUNC_SYNC_EMCY:
            return self.device_id, bytes([self.device_id])
        elif func == R.FUNC_RECEIVE_SDO:
            ccs, idx = data[0] >> 5, struct.unpack_from("<H", data, 1)[0]
            if ccs == 1:
                self.mem[idx:idx + 4] = data[4:8]
            elif ccs == 2:
                return (R.FUNC_TRANSMIT_SDO << 7) | self.device_id, bytes(self.mem[idx:idx + 4])
        elif func in (R.FUNC_RECEIVE_PDO_2, R.FUNC_RECEIVE_PDO_3):
            self.watchdog_kicks += 1
            a, b = struct.unpack_from("<ff", data)
            self.f32(R.PARAM_POSITION_TARGET, a)
            if func == R.FUNC_RECEIVE_PDO_3:
                self.f32(R.PARAM_TORQUE_TARGET, b)
            if func == R.FUNC_RECEIVE_PDO_2:
                self.f32(R.PARAM_TORQUE_TARGET, 0.0)
            if self.joint is not None and self.step_on_pdo:
                self._advance_joint(a, b if func == R.FUNC_RECEIVE_PDO_3 else 0.0)
            elif self.joint is None and func == R.FUNC_RECEIVE_PDO_3:
                self.f32(R.PARAM_TORQUE_MEASURED, b)
            second = R.PARAM_VELOCITY_MEASURED if func == R.FUNC_RECEIVE_PDO_2 else R.PARAM_TORQUE_MEASURED
            out = struct.pack("<ff", self.f32(R.PARAM_POSITION_MEASURED), self.f32(second))
            return ((func - 1) << 7) | self.device_id, out
        elif func == R.FUNC_HEARTBEAT:
            self.watchdog_kicks += 1
        return None


class DirectTransport:
    """In-process transport: frames go straight to emulated devices (no CAN)."""

    def __init__(self, devices):
        self.devices = devices
        self.rx = deque()

    def send(self, can_id, data=b""):
        for d in self.devices:
            reply = d.handle(can_id, bytes(data).ljust(8, b"\0"))
            if reply:
                self.rx.append(R.Frame(*reply))

    def recv(self, timeout):
        return self.rx.popleft() if self.rx else None

    def close(self):
        pass
