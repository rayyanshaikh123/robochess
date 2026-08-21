"""NetworkManager integration for Raspberry Pi provisioning."""

import subprocess
import socket
import requests
from dataclasses import dataclass


class NetworkManagerError(RuntimeError):
    pass


@dataclass
class NetworkStatus:
    connected: bool
    ssid: str | None = None
    ip_address: str | None = None
    internet_available: bool = False
    state: str = "network_error"
    error: str | None = None

    def to_dict(self) -> dict:
        return {
            "wifi_connected": self.connected,
            "internet_available": self.internet_available,
            "ssid": self.ssid,
            "ip_address": self.ip_address,
            "state": self.state,
            "error": self.error,
        }


class NetworkManager:
    def __init__(self, connection_name: str = "robochess-wifi") -> None:
        self.connection_name = connection_name

    def _run(self, args: list[str]) -> str:
        try:
            result = subprocess.run(
                ["nmcli", *args], capture_output=True, text=True, timeout=30, check=False
            )
        except FileNotFoundError as exc:
            raise NetworkManagerError("NetworkManager/nmcli is not installed") from exc
        if result.returncode != 0:
            raise NetworkManagerError(result.stderr.strip() or "nmcli command failed")
        return result.stdout.strip()

    @staticmethod
    def _usable_ip(value: str) -> bool:
        value = value.strip()
        return bool(value) and value not in {"127.0.0.1", "0.0.0.0"} and not value.startswith("169.254.")

    def _host_ip(self) -> str | None:
        """Return a routable host address when nmcli also reports loopback."""
        try:
            output = subprocess.run(
                ["hostname", "-I"], capture_output=True, text=True, timeout=5, check=False
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return None
        for value in output.split():
            if self._usable_ip(value):
                return value
        return None

    def status(
        self,
        internet_check_enabled: bool = True,
        internet_check_url: str = "https://connectivitycheck.gstatic.com/generate_204",
        internet_timeout: float = 5.0,
    ) -> NetworkStatus:
        try:
            output = self._run(["-t", "-f", "GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS", "device", "show"])
        except NetworkManagerError as exc:
            return NetworkStatus(False, state="network_error", error=str(exc))
        connected = "connected" in output.lower()
        ssid = None
        ip_address = None
        for line in output.splitlines():
            if "GENERAL.CONNECTION:" in line:
                ssid = line.split(":", 1)[1] or None
            if "IP4.ADDRESS" in line:
                value = line.split(":", 1)[1].split("/", 1)[0]
                if self._usable_ip(value):
                    ip_address = value
        if not ip_address:
            ip_address = self._host_ip()
        if not connected:
            return NetworkStatus(False, ssid=ssid, ip_address=ip_address, state="no_wifi")
        internet_available = False
        if internet_check_enabled:
            try:
                response = requests.get(internet_check_url, timeout=internet_timeout)
                internet_available = 200 <= response.status_code < 400
            except (requests.RequestException, socket.gaierror):
                internet_available = False
        state = "internet_available" if internet_available else "wifi_connected_no_internet"
        return NetworkStatus(
            True, ssid=ssid, ip_address=ip_address,
            internet_available=internet_available, state=state,
        )

    def configure(self, ssid: str, password: str) -> NetworkStatus:
        if not ssid.strip() or not password:
            raise NetworkManagerError("SSID and password are required")
        try:
            self._run(["connection", "delete", self.connection_name])
        except NetworkManagerError:
            # The first provisioning attempt has no existing profile.
            pass
        self._run([
            "device", "wifi", "connect", ssid,
            "password", password,
            "name", self.connection_name,
        ])
        self._run(["connection", "modify", self.connection_name, "connection.autoconnect", "yes"])
        return self.status()

    def wait_until_connected(self, attempts: int = 12, delay_seconds: float = 2.0) -> NetworkStatus:
        import time
        last = NetworkStatus(False, error="Wi-Fi connection timed out")
        for _ in range(max(1, attempts)):
            last = self.status()
            if last.connected:
                return last
            time.sleep(delay_seconds)
        return last
