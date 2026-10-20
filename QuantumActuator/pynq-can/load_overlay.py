"""Load the CAN0 (or VQC+CAN0) bitstream at boot so CAN0 EMIO reaches the Pmod pins.
Called by can0-overlay.service; does nothing if no bitstream has been installed."""
import os
import sys

BIT = "/home/xilinx/vqc_ctrl/overlay/active.bit"     # symlink to can0.bit or vqc_can0.bit
if not os.path.exists(BIT):
    print("no PL overlay installed; CAN0 EMIO not routed to pins")
    sys.exit(0)
from pynq import Overlay  # noqa: E402

Overlay(os.path.realpath(BIT))
print("loaded", os.path.realpath(BIT))
