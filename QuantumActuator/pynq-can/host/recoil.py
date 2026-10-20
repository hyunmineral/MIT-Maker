"""Recoil motor controller (B-G431B-ESC1) client over Linux SocketCAN.

Stdlib only (socket.AF_CAN), so it runs on the PYNQ image without python-can.
Protocol mirrors Recoil firmware MotorController_handleCANMessage():

    11-bit ID = (func_id << 7) | device_id          (device_id 0 = broadcast)

    NMT        0x0  host->dev  [mode, device_id]
    SYNC/PING  0x1  host->dev  []          dev->host id=device_id, [device_id]
    TPDO2/RPDO2 0x5/0x6        [pos_target f32, vel_target f32]  -> [pos, vel]
    TPDO3/RPDO3 0x7/0x8        [pos_target f32, torque_target f32] -> [pos, torque]
    TPDO4      0x9  dev->host  fast frame [pos, vel] at fast_frame_frequency
    TSDO/RSDO  0xB/0xC         [ccs<<5, idx_lo, idx_hi, 0, value u32]; read reply = [value]
    FLASH      0xD  host->dev  [1]=store, [2]=load
    HEARTBEAT  0xE  host->dev  [] (feeds the 1 s watchdog)

Any RPDO or heartbeat resets the firmware watchdog; without it the controller
drops to MODE_DAMPING after ~1 s in an active mode.
"""
from __future__ import annotations

import select
import socket
import struct
import time
from dataclasses import dataclass

# --- function codes (motor_controller_conf.h) ---
FUNC_NMT = 0x0
FUNC_SYNC_EMCY = 0x1
FUNC_TRANSMIT_PDO_1 = 0x3
FUNC_RECEIVE_PDO_1 = 0x4
FUNC_TRANSMIT_PDO_2 = 0x5
FUNC_RECEIVE_PDO_2 = 0x6
FUNC_TRANSMIT_PDO_3 = 0x7
FUNC_RECEIVE_PDO_3 = 0x8
FUNC_TRANSMIT_PDO_4 = 0x9
FUNC_TRANSMIT_SDO = 0xB
FUNC_RECEIVE_SDO = 0xC
FUNC_FLASH = 0xD
FUNC_HEARTBEAT = 0xE

# --- modes ---
MODE_DISABLED = 0x00
MODE_IDLE = 0x01
MODE_DAMPING = 0x02
MODE_CALIBRATION = 0x05
MODE_CURRENT = 0x10
MODE_TORQUE = 0x11
MODE_VELOCITY = 0x12
MODE_POSITION = 0x13
MODE_VALPHABETA_OVERRIDE = 0x21   # open-loop voltage vector (OPENLOOP_NO_ENCODER firmware)
MODE_DEBUG = 0x80
MODE_NAMES = {v: k[5:] for k, v in globals().items() if k.startswith("MODE_")}

# --- parameter offsets used by the host (byte offsets into MotorController) ---
PARAM_DEVICE_ID = 0x000
PARAM_FIRMWARE_VERSION = 0x004
PARAM_WATCHDOG_TIMEOUT = 0x008
PARAM_FAST_FRAME_FREQUENCY = 0x00C
PARAM_MODE = 0x010
PARAM_ERROR = 0x014
PARAM_GEAR_RATIO = 0x01C
PARAM_POSITION_KP = 0x020
PARAM_POSITION_KI = 0x024
PARAM_VELOCITY_KP = 0x028
PARAM_VELOCITY_KI = 0x02C
PARAM_TORQUE_LIMIT = 0x030
PARAM_VELOCITY_LIMIT = 0x034
PARAM_POSITION_LIMIT_LOWER = 0x038
PARAM_POSITION_LIMIT_UPPER = 0x03C
PARAM_POSITION_OFFSET = 0x040
PARAM_TORQUE_TARGET = 0x044
PARAM_TORQUE_MEASURED = 0x048
PARAM_VELOCITY_MEASURED = 0x054
PARAM_POSITION_TARGET = 0x05C
PARAM_POSITION_MEASURED = 0x060
PARAM_CURRENT_LIMIT = 0x074
PARAM_BUS_VOLTAGE_MEASURED = 0x100
PARAM_MOTOR_POLE_PAIRS = 0x104
PARAM_MOTOR_TORQUE_CONSTANT = 0x108
PARAM_ENCODER_FLUX_OFFSET = 0x13C

_CAN_FMT = "=IB3x8s"
_CAN_SIZE = struct.calcsize(_CAN_FMT)
_CAN_EFF_FLAG = 0x80000000
_CAN_RTR_FLAG = 0x40000000
_CAN_ERR_FLAG = 0x20000000


def make_id(func: int, device_id: int) -> int:
    return (func << 7) | (device_id & 0x7F)


def split_id(can_id: int) -> tuple[int, int]:
    return can_id >> 7, can_id & 0x7F


class RecoilTimeout(TimeoutError):
    pass


@dataclass
class Frame:
    can_id: int
    data: bytes

    @property
    def func(self) -> int:
        return self.can_id >> 7

    @property
    def device_id(self) -> int:
        return self.can_id & 0x7F


# Frames a host should receive (device -> host) and a device should receive (host -> device).
# Function code 0 is shared by NMT (host->dev) and the ping reply (dev->host).
HOST_RX_FUNCS = (FUNC_NMT, FUNC_TRANSMIT_PDO_1, FUNC_TRANSMIT_PDO_2, FUNC_TRANSMIT_PDO_3,
                 FUNC_TRANSMIT_PDO_4, FUNC_TRANSMIT_SDO)
DEVICE_RX_FUNCS = (FUNC_NMT, FUNC_SYNC_EMCY, FUNC_RECEIVE_PDO_1, FUNC_RECEIVE_PDO_2, FUNC_RECEIVE_PDO_3,
                   FUNC_RECEIVE_SDO, FUNC_FLASH, FUNC_HEARTBEAT)


class SocketCANTransport:
    """Raw SocketCAN, standard 11-bit data frames only.

    rx_funcs installs a kernel CAN_RAW_FILTER on the function code, so a host
    never sees host->device traffic (e.g. its own frames echoed back when the
    controller is in loopback mode).
    """

    def __init__(self, channel: str = "can0", rx_funcs=HOST_RX_FUNCS):
        self.sock = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
        if rx_funcs is not None:
            flt = b"".join(struct.pack("=II", f << 7, 0xF << 7 | _CAN_EFF_FLAG | _CAN_RTR_FLAG) for f in rx_funcs)
            self.sock.setsockopt(socket.SOL_CAN_RAW, socket.CAN_RAW_FILTER, flt)
        self.sock.bind((channel,))
        self.sock.setblocking(False)

    def send(self, can_id: int, data: bytes = b"") -> None:
        self.sock.send(struct.pack(_CAN_FMT, can_id, len(data), data.ljust(8, b"\0")))

    def recv(self, timeout: float) -> Frame | None:
        r, _, _ = select.select([self.sock], [], [], max(timeout, 0.0))
        if not r:
            return None
        can_id, dlc, data = struct.unpack(_CAN_FMT, self.sock.recv(_CAN_SIZE))
        if can_id & (_CAN_EFF_FLAG | _CAN_RTR_FLAG | _CAN_ERR_FLAG):
            return Frame(-1, b"")
        return Frame(can_id, data[:dlc])

    def close(self) -> None:
        self.sock.close()


class SlcanTransport:
    """USB-CAN adapter running SLCAN (Lawicel ASCII) firmware, e.g. CANable 2.0 with the
    normaldotcom/canable2 firmware (shows up as /dev/ttyACM0).

    Stdlib only (termios + os), because the PYNQ image has neither the slcan kernel module,
    pyserial nor python-can. Same interface as SocketCANTransport; rx_funcs is applied in software.
    """

    _BITRATE_CMD = {10_000: "S0", 20_000: "S1", 50_000: "S2", 100_000: "S3", 125_000: "S4",
                    250_000: "S5", 500_000: "S6", 750_000: "S7", 1_000_000: "S8"}

    def __init__(self, device: str = "/dev/ttyACM0", bitrate: int = 1_000_000, rx_funcs=HOST_RX_FUNCS):
        import os
        import termios
        import tty
        self._os = os
        self.fd = os.open(device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        tty.setraw(self.fd)
        attrs = termios.tcgetattr(self.fd)
        attrs[2] |= termios.CLOCAL | termios.CREAD
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        termios.tcflush(self.fd, termios.TCIOFLUSH)
        self.rx_funcs = None if rx_funcs is None else set(rx_funcs)
        self._buf = b""
        self._frames: list[Frame] = []
        for cmd in ("C", "C", self._BITRATE_CMD[bitrate], "O"):   # close twice: clears a half-sent line
            self._write(cmd)
            time.sleep(0.02)
        self._read_available()
        self._frames.clear()

    def _write(self, line: str) -> None:
        data = (line + "\r").encode()
        while data:
            try:
                n = self._os.write(self.fd, data)
                data = data[n:]
            except BlockingIOError:
                select.select([], [self.fd], [], 0.01)

    def _read_available(self) -> None:
        while True:
            try:
                chunk = self._os.read(self.fd, 4096)
            except BlockingIOError:
                break
            if not chunk:
                break
            self._buf += chunk
        *lines, self._buf = self._buf.replace(b"\x07", b"\r").split(b"\r")
        for line in lines:
            f = self._parse(line)
            if f is not None and (self.rx_funcs is None or f.func in self.rx_funcs):
                self._frames.append(f)

    @staticmethod
    def _parse(line: bytes) -> Frame | None:
        # standard data frame: t III L DD..  (ignore 'z'/'Z' tx acks, extended and remote frames)
        if len(line) < 5 or line[:1] != b"t":
            return None
        try:
            can_id = int(line[1:4], 16)
            dlc = int(line[4:5], 16)
            data = bytes.fromhex(line[5:5 + 2 * dlc].decode())
        except ValueError:
            return None
        return Frame(can_id, data) if len(data) == dlc else None

    def send(self, can_id: int, data: bytes = b"") -> None:
        self._write(f"t{can_id:03X}{len(data):X}{data.hex().upper()}")

    def recv(self, timeout: float) -> Frame | None:
        deadline = time.monotonic() + max(timeout, 0.0)
        while True:
            if not self._frames:
                self._read_available()
            if self._frames:
                return self._frames.pop(0)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            select.select([self.fd], [], [], remaining)

    def close(self) -> None:
        try:
            self._write("C")
        finally:
            self._os.close(self.fd)


def open_transport(channel: str = "can0"):
    """'can0' -> SocketCAN, '/dev/ttyACM0' or 'slcan:/dev/ttyACM0' -> SLCAN adapter."""
    if channel.startswith("slcan:"):
        return SlcanTransport(channel[len("slcan:"):])
    if channel.startswith("/dev/"):
        return SlcanTransport(channel)
    return SocketCANTransport(channel)


class RecoilBus:
    def __init__(self, transport=None, channel: str = "can0", timeout: float = 0.02):
        self.t = transport if transport is not None else open_transport(channel)
        self.timeout = timeout

    def close(self) -> None:
        self.t.close()

    # --- low level -------------------------------------------------------
    def _transact(self, can_id: int, data: bytes, reply_id: int | None, timeout: float | None = None) -> bytes | None:
        if reply_id is not None:
            # The protocol has no sequence numbers: any frame still queued is a late
            # reply to an earlier request and must not be mistaken for this one.
            self.flush()
        self.t.send(can_id, data)
        if reply_id is None:
            return None
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RecoilTimeout(f"no reply 0x{reply_id:03X} to 0x{can_id:03X}")
            f = self.t.recv(remaining)
            if f is not None and f.can_id == reply_id:
                return f.data

    def flush(self) -> int:
        n = 0
        while self.t.recv(0) is not None:
            n += 1
        return n

    # --- services --------------------------------------------------------
    def ping(self, device_id: int, timeout: float | None = None) -> bool:
        try:
            data = self._transact(make_id(FUNC_SYNC_EMCY, device_id), b"", make_id(FUNC_NMT, device_id), timeout)
        except RecoilTimeout:
            return False
        return len(data) >= 1 and data[0] == device_id

    def scan(self, ids=range(1, 64), timeout: float = 0.005) -> list[int]:
        return [i for i in ids if self.ping(i, timeout)]

    def set_mode(self, device_id: int, mode: int) -> None:
        self.t.send(make_id(FUNC_NMT, 0), bytes([mode, device_id]))

    def heartbeat(self, device_id: int) -> None:
        self.t.send(make_id(FUNC_HEARTBEAT, device_id))

    def read_u32(self, device_id: int, param: int) -> int:
        data = self._transact(make_id(FUNC_RECEIVE_SDO, device_id),
                              struct.pack("<BH5x", 2 << 5, param),
                              make_id(FUNC_TRANSMIT_SDO, device_id))
        return struct.unpack("<I", data[:4])[0]

    def read_f32(self, device_id: int, param: int) -> float:
        return struct.unpack("<f", struct.pack("<I", self.read_u32(device_id, param)))[0]

    def write_u32(self, device_id: int, param: int, value: int) -> None:
        self.t.send(make_id(FUNC_RECEIVE_SDO, device_id), struct.pack("<BHxI", 1 << 5, param, value & 0xFFFFFFFF))

    def write_f32(self, device_id: int, param: int, value: float) -> None:
        self.t.send(make_id(FUNC_RECEIVE_SDO, device_id), struct.pack("<BHxf", 1 << 5, param, value))

    def store_config(self, device_id: int) -> None:
        self.t.send(make_id(FUNC_FLASH, device_id), b"\x01")

    def load_config(self, device_id: int) -> None:
        self.t.send(make_id(FUNC_FLASH, device_id), b"\x02")

    # --- real-time PDOs --------------------------------------------------
    def pdo_position_velocity(self, device_id: int, position: float, velocity: float = 0.0) -> tuple[float, float]:
        data = self._transact(make_id(FUNC_RECEIVE_PDO_2, device_id), struct.pack("<ff", position, velocity),
                              make_id(FUNC_TRANSMIT_PDO_2, device_id))
        return struct.unpack("<ff", data[:8])

    def pdo_position_torque(self, device_id: int, position: float, torque: float,
                            timeout: float | None = None) -> tuple[float, float]:
        """RPDO3: sets position target and torque feed-forward/target.

        Returns (position_measured, torque_measured) [rad, N*m] at the output shaft.
        """
        data = self._transact(make_id(FUNC_RECEIVE_PDO_3, device_id), struct.pack("<ff", position, torque),
                              make_id(FUNC_TRANSMIT_PDO_3, device_id), timeout)
        return struct.unpack("<ff", data[:8])

    # --- convenience -----------------------------------------------------
    def info(self, device_id: int) -> dict:
        mode = self.read_u32(device_id, PARAM_MODE)
        return {
            "device_id": self.read_u32(device_id, PARAM_DEVICE_ID),
            "firmware": f"0x{self.read_u32(device_id, PARAM_FIRMWARE_VERSION):08X}",
            "mode": MODE_NAMES.get(mode, hex(mode)),
            "error": f"0x{self.read_u32(device_id, PARAM_ERROR):08X}",
            "bus_voltage": round(self.read_f32(device_id, PARAM_BUS_VOLTAGE_MEASURED), 3),
            "position": round(self.read_f32(device_id, PARAM_POSITION_MEASURED), 5),
            "velocity": round(self.read_f32(device_id, PARAM_VELOCITY_MEASURED), 5),
            "gear_ratio": round(self.read_f32(device_id, PARAM_GEAR_RATIO), 4),
            "torque_limit": round(self.read_f32(device_id, PARAM_TORQUE_LIMIT), 4),
            "position_kp": round(self.read_f32(device_id, PARAM_POSITION_KP), 4),
            "velocity_kp": round(self.read_f32(device_id, PARAM_VELOCITY_KP), 4),
            "flux_offset": round(self.read_f32(device_id, PARAM_ENCODER_FLUX_OFFSET), 6),
        }
