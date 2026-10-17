"""Protocol tests for recoil.py against an emulation of the Recoil firmware's
MotorController_handleCANMessage(). Runs anywhere: python test_recoil.py"""
import unittest

import recoil as R
from recoil_emulator import DirectTransport, FakeRecoil


class RecoilProtocolTest(unittest.TestCase):
    def setUp(self):
        self.dev = FakeRecoil(device_id=1)
        self.bus = R.RecoilBus(DirectTransport([self.dev, FakeRecoil(device_id=7)]), timeout=0.001)

    def test_ping_and_scan(self):
        self.assertTrue(self.bus.ping(1))
        self.assertFalse(self.bus.ping(2))
        self.assertEqual(self.bus.scan(range(1, 10), timeout=0.001), [1, 7])

    def test_sdo_read_write(self):
        self.assertEqual(self.bus.read_u32(1, R.PARAM_FIRMWARE_VERSION), 0x20250226)
        self.assertAlmostEqual(self.bus.read_f32(1, R.PARAM_GEAR_RATIO), 1.0)   # firmware default
        self.bus.write_f32(1, R.PARAM_POSITION_KP, 12.5)
        self.assertAlmostEqual(self.bus.read_f32(1, R.PARAM_POSITION_KP), 12.5)
        self.assertEqual(self.bus.read_f32(7, R.PARAM_POSITION_KP), 50.0)  # other device untouched

    def test_mode(self):
        self.bus.set_mode(1, R.MODE_POSITION)
        self.assertEqual(self.bus.read_u32(1, R.PARAM_MODE), R.MODE_POSITION)
        self.assertEqual(self.bus.read_u32(7, R.PARAM_MODE), R.MODE_IDLE)
        self.assertEqual(self.bus.info(1)["mode"], "POSITION")

    def test_pdo(self):
        pos, tau = self.bus.pdo_position_torque(1, 1.0, 0.3)
        self.assertAlmostEqual(pos, 0.25)
        self.assertAlmostEqual(tau, 0.3, places=6)
        self.assertAlmostEqual(self.bus.read_f32(1, R.PARAM_POSITION_TARGET), 1.0)
        pos, vel = self.bus.pdo_position_velocity(1, 0.5, 0.0)
        self.assertAlmostEqual(pos, 0.25)
        self.assertEqual(self.dev.watchdog_kicks, 2)

    def test_timeout(self):
        with self.assertRaises(R.RecoilTimeout):
            self.bus.read_u32(9, R.PARAM_MODE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
