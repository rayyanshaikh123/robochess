import shutil
import subprocess
from typing import Optional


class BleAdvertiser:
    def start(self, token: str) -> None:
        raise NotImplementedError()

    def stop(self) -> None:
        raise NotImplementedError()


class ConsoleBleAdvertiser(BleAdvertiser):
    def __init__(self, prefix: str = "BLE token") -> None:
        self.prefix = prefix
        self._last_token: Optional[str] = None

    def start(self, token: str) -> None:
        if token == self._last_token:
            return
        self._last_token = token
        print(f"{self.prefix}: {token}")

    def stop(self) -> None:
        return


class BluezBleAdvertiser(BleAdvertiser):
    def __init__(self, service_uuid: str) -> None:
        self.service_uuid = service_uuid
        self._active = False
        self._last_token: Optional[str] = None

    def start(self, token: str) -> None:
        if not shutil.which("bluetoothctl"):
            raise RuntimeError("bluetoothctl not found")
        if token == self._last_token and self._active:
            return
        self._last_token = token
        self._run_advertise(token)
        self._active = True

    def stop(self) -> None:
        if not self._active:
            return
        self._run_commands([
            "menu advertise",
            "advertise off",
            "back",
            "exit",
        ])
        self._active = False

    def _run_advertise(self, token: str) -> None:
        data_hex = token.encode("utf-8").hex()
        commands = [
            "menu advertise",
            "clear",
            f"uuid {self.service_uuid}",
            f"service-data {self.service_uuid} {data_hex}",
            "advertise on",
            "back",
            "exit",
        ]
        self._run_commands(commands)

    def _run_commands(self, commands: list[str]) -> None:
        payload = "\n".join(commands) + "\n"
        result = subprocess.run(
            ["bluetoothctl"],
            input=payload,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError("bluetoothctl failed")


def create_ble_advertiser(mode: str, service_uuid: str) -> BleAdvertiser:
    normalized = mode.strip().lower()
    if normalized == "bluez":
        return BluezBleAdvertiser(service_uuid)
    return ConsoleBleAdvertiser()
