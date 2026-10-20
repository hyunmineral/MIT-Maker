"""PS CAN0 internal-loopback self test (no transceiver needed).

Run on PYNQ after: ip link set can0 up type can bitrate 1000000 loopback on
Sends N frames, receives them back, reports round-trip latency stats.
"""
import socket, struct, time, statistics, sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
FMT = "=IB3x8s"

s = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
s.setsockopt(socket.SOL_CAN_RAW, socket.CAN_RAW_RECV_OWN_MSGS, 0)  # count only frames that came back through the controller
s.bind(("can0",))
s.settimeout(0.1)

lat, bad, lost = [], 0, 0
for i in range(N):
    data = struct.pack("<Q", i)
    t0 = time.perf_counter_ns()
    s.send(struct.pack(FMT, 0x123, 8, data))
    try:
        while True:
            can_id, dlc, rx = struct.unpack(FMT, s.recv(16))
            if can_id == 0x123 and rx == data:
                lat.append((time.perf_counter_ns() - t0) / 1000)
                break
            bad += 1
    except socket.timeout:
        lost += 1

print(f"sent={N} ok={len(lat)} lost={lost} mismatched={bad}")
if lat:
    lat.sort()
    p = lambda q: lat[min(len(lat) - 1, int(q * len(lat)))]
    print(f"RTT us: min={lat[0]:.1f} median={statistics.median(lat):.1f} "
          f"p99={p(0.99):.1f} max={lat[-1]:.1f}")
