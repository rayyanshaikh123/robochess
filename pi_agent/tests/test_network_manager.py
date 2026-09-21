import unittest

from pi_agent.network_manager import NetworkManager


class FakeNetworkManager(NetworkManager):
    def __init__(self, output: str):
        super().__init__()
        self.output = output

    def _run(self, args: list[str]) -> str:
        self.last_args = args
        return self.output


class NetworkManagerTests(unittest.TestCase):
    def test_scan_wifi_deduplicates_and_sorts_by_signal(self):
        manager = FakeNetworkManager(
            "Cafe:42:WPA2\n"
            "Home:88:WPA2\n"
            "Cafe:65:WPA2\n"
            "Open:88:\n"
            ":90:WPA2\n"
            "malformed\n"
        )

        networks = manager.scan_wifi()

        self.assertEqual(
            networks,
            [
                {"ssid": "Home", "signal": 88, "security": "WPA2"},
                {"ssid": "Open", "signal": 88, "security": "open"},
                {"ssid": "Cafe", "signal": 65, "security": "WPA2"},
            ],
        )
        self.assertIn("--rescan", manager.last_args)


if __name__ == "__main__":
    unittest.main()
