"""Transport-neutral GATT session adapter.

Platform-specific BlueZ registration can call ``on_write`` from the RX
characteristic and publish returned bytes through the TX characteristic.
Keeping this adapter transport-neutral makes protocol tests run without Pi
hardware and prevents BLE code from becoming the game authority.
"""

from collections.abc import Callable

from .ble_protocol import Message, SessionProtocol


class GattSession:
    def __init__(self, state_handler: Callable[[Message], Message]) -> None:
        self.protocol = SessionProtocol(state_handler)
        self.authorized = False

    def authorize(self, device_id: str, token: str, expected_device_id: str, expected_token: str) -> bool:
        self.authorized = device_id == expected_device_id and token == expected_token
        return self.authorized

    def on_write(self, value: bytes) -> bytes:
        if not self.authorized:
            return Message("error", payload={"reason": "not_authorized"}).encode()
        return self.protocol.handle(value)
