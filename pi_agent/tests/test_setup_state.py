import unittest

from pi_agent.setup_state import SetupReadiness


class SetupReadinessTests(unittest.TestCase):
    def setUp(self):
        self.readiness = SetupReadiness(vision_mode="cloud", vision_require_internet=True)
        self.network = {
            "wifi_connected": True,
            "internet_available": True,
            "state": "internet_available",
        }
        self.detector = {
            "model_available": True,
            "last_error": None,
            "camera": {"opened": True, "capture_devices": ["/dev/video0"]},
        }
        self.gantry = {"homed": True}

    def test_cloud_setup_is_blocked_until_starting_position_is_valid(self):
        result = self.readiness.evaluate(self.network, self.detector, True, self.gantry)
        self.assertFalse(result["ready"])
        self.assertEqual(result["missing"], ["starting_position_valid"])

    def test_all_required_stages_report_ready(self):
        self.readiness.mark_starting_position(True)
        result = self.readiness.evaluate(self.network, self.detector, True, self.gantry)
        self.assertTrue(result["ready"])
        self.assertEqual(result["missing"], [])

    def test_cloud_setup_requires_internet_even_when_wifi_is_connected(self):
        self.readiness.mark_starting_position(True)
        offline = {**self.network, "internet_available": False, "state": "wifi_connected_no_internet"}
        result = self.readiness.evaluate(offline, self.detector, True, self.gantry)
        self.assertFalse(result["ready"])
        self.assertIn("wifi_ready", result["missing"])
        self.assertIn("roboflow_ready", result["missing"])


if __name__ == "__main__":
    unittest.main()
