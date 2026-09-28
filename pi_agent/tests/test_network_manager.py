import unittest

from pi_agent.network_manager import NetworkManager, NetworkManagerError


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
            # scan_wifi asks nmcli for tab-separated fields.
            "Cafe\t42\tWPA2\n"
            "Home\t88\tWPA2\n"
            "Cafe\t65\tWPA2\n"
            "Open\t88\t\n"
            "\t90\tWPA2\n"
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


class ScriptedNetworkManager(NetworkManager):
    """Answers each nmcli call by its arguments, like a real Pi would."""

    def __init__(self, responses: dict, host_ip: str | None = None):
        super().__init__()
        self.responses = responses
        self.host_ip = host_ip

    def _run(self, args: list[str]) -> str:
        for key, value in self.responses.items():
            if key in " ".join(args):
                if isinstance(value, Exception):
                    raise value
                return value
        raise NetworkManagerError("unexpected nmcli call: " + " ".join(args))

    def _host_ip(self):
        return self.host_ip


# `nmcli device status` on Raspberry Pi OS Bookworm set up with Pi Imager.
_PI_IMAGER_STATUS = (
    "wlan0:wifi:connected:preconfigured\n"
    "lo:loopback:connected (externally):lo\n"
    "p2p-dev-wlan0:wifi-p2p:disconnected:\n"
    "eth0:ethernet:unavailable:\n"
)


class NetworkStatusTests(unittest.TestCase):
    def status(self, manager):
        return manager.status(internet_check_enabled=False)

    def test_pi_imager_wifi_reports_connected_with_real_ssid_and_ip(self):
        manager = ScriptedNetworkManager({
            "device status": _PI_IMAGER_STATUS,
            "IP4.ADDRESS device show wlan0": "192.168.0.219/24",
            "ACTIVE,SSID": "no:Neighbour\nyes:Home\\:5G\n",
        })
        result = self.status(manager)
        self.assertTrue(result.connected)
        self.assertEqual(result.ip_address, "192.168.0.219")
        self.assertEqual(result.ssid, "Home:5G")

    def test_disconnected_wifi_is_not_mistaken_for_connected(self):
        manager = ScriptedNetworkManager({
            "device status": "wlan0:wifi:disconnected:\nlo:loopback:connected (externally):lo\n",
        })
        result = self.status(manager)
        self.assertFalse(result.connected)
        self.assertEqual(result.state, "no_wifi")

    def test_ethernet_only_counts_as_online(self):
        manager = ScriptedNetworkManager({
            "device status": "eth0:ethernet:connected:Wired connection 1\nwlan0:wifi:disconnected:\n",
            "IP4.ADDRESS device show eth0": "10.0.0.5/24",
        })
        result = self.status(manager)
        self.assertTrue(result.connected)
        self.assertEqual(result.ip_address, "10.0.0.5")

    def test_nmcli_failure_falls_back_to_host_ip(self):
        manager = ScriptedNetworkManager(
            {"device status": NetworkManagerError("NetworkManager is not running")},
            host_ip="192.168.1.50",
        )
        result = self.status(manager)
        self.assertTrue(result.connected)
        self.assertEqual(result.ip_address, "192.168.1.50")

    def test_nmcli_failure_without_ip_reports_error(self):
        manager = ScriptedNetworkManager(
            {"device status": NetworkManagerError("NetworkManager is not running")},
        )
        result = self.status(manager)
        self.assertFalse(result.connected)
        self.assertEqual(result.state, "network_error")


if __name__ == "__main__":
    unittest.main()
