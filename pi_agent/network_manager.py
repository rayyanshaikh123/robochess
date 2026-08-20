"""NetworkManager integration for Raspberry Pi provisioning."""

import json
import subprocess
from dataclasses import dataclass


class NetworkManagerError(RuntimeError):
    pass


@dataclass
class NetworkStatus:
    connected: bool
    ssid: str | None = None
    error: str | None = None


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

    def status(self) -> NetworkStatus:
        try:
            output = self._run(["-t", "-f", "GENERAL.STATE,GENERAL.CONNECTION", "device", "show"])
        except NetworkManagerError as exc:
            return NetworkStatus(False, error=str(exc))
        connected = "connected" in output.lower()
        ssid = None
        for line in output.splitlines():
            if "GENERAL.CONNECTION:" in line:
                ssid = line.split(":", 1)[1] or None
        return NetworkStatus(connected, ssid=ssid)

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
