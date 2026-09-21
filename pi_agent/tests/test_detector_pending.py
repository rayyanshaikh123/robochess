import threading
import unittest

from pi_agent.camera_detector import PiCameraDetector


class DetectorPendingMoveTests(unittest.TestCase):
    def test_pending_move_is_taken_once_with_san_and_version(self):
        detector = PiCameraDetector.__new__(PiCameraDetector)
        detector._lock = threading.Lock()
        detector.pending_auto_move = "e2e4"
        detector.pending_auto_san = "e4"
        detector.pending_auto_version = 3

        first = detector.take_pending_move()
        second = detector.take_pending_move()

        self.assertEqual(first, {"uci": "e2e4", "san": "e4", "version": 3})
        self.assertIsNone(second)
        self.assertIsNone(detector.pending_auto_move)
        self.assertIsNone(detector.pending_auto_san)


if __name__ == "__main__":
    unittest.main()
