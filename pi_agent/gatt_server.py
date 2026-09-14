"""BLE provisioning adapter.

The production path uses BlueZ through the optional ``bluezero`` package. The
callbacks are kept independent from BlueZ so they can be tested on a laptop.
"""

from collections.abc import Callable
import json
import threading
import time

from pi_agent.ble_protocol import (
    CONTROL_UUID,
    DEVICE_INFO_UUID,
    PROTOCOL_VERSION,
    SERVICE_UUID,
    STATUS_UUID,
    WIFI_UUID,
    decode_message,
    encode_chunks,
    envelope,
    validate_game_message,
)


class GattServer:
    def __init__(
        self,
        device_id: str,
        on_control: Callable[[dict], dict] | None = None,
        on_wifi: Callable[[dict], dict] | None = None,
        name: str | None = None,
        adapter_address: str | None = None,
        require_bond: bool = False,
    ) -> None:
        self.device_id = device_id

        # A 128-bit service UUID leaves little room in a legacy BLE advert.
        # Keep this short; the complete ID is readable from DEVICE_INFO_UUID.
        self.name = name or f"RC-{device_id[-3:]}"

        self.on_control = on_control
        self.on_wifi = on_wifi

        # Initial board state before provisioning.
        # Status messages are compact (no request_id) so the payload always
        # fits in a single BLE read response (< 180 bytes).
        self._status = {
            "version": PROTOCOL_VERSION,
            "type": "status",
            "device_id": device_id,
            "data": {"status": "unpaired"},
        }

        # Buffers for BLE messages that may arrive in multiple writes.
        self._control_buffer = bytearray()
        self._wifi_buffer = bytearray()

        self._published = False
        self._peripheral = None

        self._game_handler: Callable[[dict], dict] | None = None

        # GATT characteristic references.
        self._control_characteristic = None
        self._wifi_characteristic = None
        self._status_characteristic = None
        # BlueZ/GATT notifications must be serialized.  Setting a
        # characteristic repeatedly in the same callback can replace an
        # earlier notification before the central has received it.
        self._send_lock = threading.Lock()

        self._thread: threading.Thread | None = None
        self.adapter_address = adapter_address
        self.require_bond = require_bond

    def handle_control(self, raw: bytes) -> list[bytes]:
        """Process a message received through the Control characteristic."""

        self._control_buffer.extend(raw)

        try:
            message = decode_message(bytes(self._control_buffer))
        except (ValueError, json.JSONDecodeError):
            # Message may be incomplete because BLE writes can be fragmented.
            return []

        self._control_buffer.clear()
        print(f"BLE control received: {message.get('type')}", flush=True)

        if message.get("device_id") not in {None, self.device_id}:
            result = {"status": "error", "error": "Device ID mismatch"}
            return encode_chunks(
                envelope("control.result", self.device_id, **result)
            )

        if message.get("type") in {
            "session.start",
            "session.reset",
            "session.resume",
            "session.undo",
            "state.request",
            "move.propose",
            "gantry.home",
            "gantry.status",
            "camera.calibrate",
            "camera.status",
        }:
            try:
                validate_game_message(message)

                result = (
                    self._game_handler(message)
                    if self._game_handler
                    else {"status": "unsupported"}
                )

            except ValueError as exc:
                result = {
                    "status": "error",
                    "error": str(exc),
                }

            self._status = {
                "version": PROTOCOL_VERSION,
                "type": "game.state",
                "device_id": self.device_id,
                "data": result,
            }

        else:
            result = (
                self.on_control(message)
                if self.on_control
                else {"status": "ok"}
            )

        return encode_chunks(
            envelope(
                "control.result",
                self.device_id,
                **result,
            )
        )

    def set_game_handler(self, handler: Callable[[dict], dict]) -> None:
        """Attach the Pi-owned game command handler before publishing GATT."""

        self._game_handler = handler

    def _on_control_write(
        self,
        value: list[int],
        _: dict,
    ) -> None:
        """Handle writes received on the Control characteristic.

        Dispatches to a background thread so the GLib/BLE event loop is never
        blocked by slow operations (e.g. internet-connectivity checks).
        """

        raw = bytes(value)
        threading.Thread(
            target=self._handle_control_in_bg,
            args=(raw,),
            daemon=True,
            name="robochess-ble-ctrl",
        ).start()

    def _handle_control_in_bg(self, raw: bytes) -> None:
        replies = self.handle_control(raw)
        self._send_replies(self._control_characteristic, replies)
        self._publish_status()

    def _on_wifi_write(
        self,
        value: list[int],
        _: dict,
    ) -> None:
        """Handle Wi-Fi provisioning messages received through F010.

        Dispatched to a background thread so the GLib event loop is not
        blocked while waiting for the network to associate.
        """

        raw = bytes(value)
        threading.Thread(
            target=self._handle_wifi_in_bg,
            args=(raw,),
            daemon=True,
            name="robochess-ble-wifi",
        ).start()

    def _handle_wifi_in_bg(self, raw: bytes) -> None:
        replies = self.handle_wifi(raw)
        # IMPORTANT:
        # Wi-Fi responses must be written to F010, not F00F.
        self._send_replies(self._wifi_characteristic, replies)
        # Publish the updated provisioning/network status through F011.
        self._publish_status()

    def _publish_status(self) -> None:
        """Update the Status characteristic with the current status payload."""

        self._send_replies(self._status_characteristic, encode_chunks(self._status))

    def _send_replies(self, characteristic: object | None, replies: list[bytes]) -> None:
        """Emit response frames one at a time so BLE notifications are not lost."""
        if not characteristic or not replies:
            return
        with self._send_lock:
            for index, reply in enumerate(replies):
                characteristic.set_value(list(reply))
                # BlueZ may coalesce rapid value changes. Give the controller
                # time to transmit each notification before replacing it.
                if index + 1 < len(replies):
                    time.sleep(0.02)

    def handle_wifi(self, raw: bytes) -> list[bytes]:
        """Decode and process a Wi-Fi provisioning message."""

        self._wifi_buffer.extend(raw)

        try:
            message = decode_message(
                bytes(self._wifi_buffer)
            )
        except (ValueError, json.JSONDecodeError):
            # The message may not be complete yet.
            return []

        self._wifi_buffer.clear()

        if message.get("device_id") not in {None, self.device_id}:
            result = {"status": "error", "error": "Device ID mismatch"}
        else:
            result = (
                self.on_wifi(message)
                if self.on_wifi
                else {"status": "unsupported"}
            )

        # Update the board status based on the provisioning result.
        if result.get("status") == "wifi_connected":
            network = result.get("network") or {}
            self._status = {
                "version": PROTOCOL_VERSION,
                "type": "status",
                "device_id": self.device_id,
                "data": {
                    "status": "wifi_connected",
                    "ssid": result.get("ssid"),
                    "ip_address": network.get("ip_address"),
                },
            }

        elif result.get("status") == "error":
            self._status = {
                "version": PROTOCOL_VERSION,
                "type": "status",
                "device_id": self.device_id,
                "data": {
                    "status": "error",
                    "error": result.get("error"),
                },
            }

        return encode_chunks(
            envelope(
                "wifi.result",
                self.device_id,
                **result,
            )
        )

    def status_payload(self) -> bytes:
        """Compatibility accessor for the first status transport frame."""
        return encode_chunks(self._status)[0]

    def publish(self) -> None:
        """Create and publish the RoboChess GATT server."""

        try:
            from bluezero import adapter, peripheral
        except ImportError as exc:
            raise RuntimeError(
                "Install bluezero and run on a BlueZ-enabled Raspberry Pi"
            ) from exc

        try:
            address = (
                self.adapter_address
                or adapter.list_adapters()[0]
            )
        except Exception as exc:
            raise RuntimeError(
                "No usable Bluetooth adapter. Check "
                "`systemctl status bluetooth` and "
                "`bluetoothctl show`."
            ) from exc

        self._peripheral = peripheral.Peripheral(
            adapter_address=address,
            local_name=self.name,
            appearance=0x0000,
        )

        # ============================================================
        # RoboChess primary BLE service
        # ============================================================

        self._peripheral.add_service(
            srv_id=1,
            uuid=SERVICE_UUID,
            primary=True,
        )

        # ============================================================
        # F00E - Device Information
        # ============================================================

        self._peripheral.add_characteristic(
            srv_id=1,
            chr_id=1,
            uuid=DEVICE_INFO_UUID,
            value=[
                ord(c)
                for c in self.device_id
            ],
            notifying=False,
            flags=["read"],
        )

        # ============================================================
        # F00F - Control
        # ============================================================

        self._peripheral.add_characteristic(
            srv_id=1,
            chr_id=2,
            uuid=CONTROL_UUID,
            value=[],

            # BlueZ rejects unauthenticated writes before they reach
            # the Pi.
            notifying=True,
            flags=[
                "write",
                "write-without-response",
                "notify",
            ] + (["encrypt-authenticated-write"] if self.require_bond else []),
            write_callback=self._on_control_write,
        )

        self._control_characteristic = (
            self._peripheral.characteristics[-1]
        )

        # ============================================================
        # F010 - Wi-Fi Provisioning
        # ============================================================

        self._peripheral.add_characteristic(
            srv_id=1,
            chr_id=3,
            uuid=WIFI_UUID,
            value=[],
            notifying=True,
            flags=[
                "write",
                "write-without-response",
                "notify",
            ] + (["encrypt-authenticated-write"] if self.require_bond else []),
            write_callback=self._on_wifi_write,
        )

        # Keep a direct reference to F010 so Wi-Fi responses are
        # written back to the correct characteristic.
        self._wifi_characteristic = (
            self._peripheral.characteristics[-1]
        )

        # ============================================================
        # F011 - Status
        # ============================================================

        self._peripheral.add_characteristic(
            srv_id=1,
            chr_id=4,
            uuid=STATUS_UUID,
            value=list(self.status_payload()),
            notifying=False,
            flags=[
                "read",
                "notify",
            ],
        )

        self._status_characteristic = (
            self._peripheral.characteristics[-1]
        )

        # BlueZero owns a GLib loop in publish(); keep the board
        # controller alive.
        self._thread = threading.Thread(
            target=self._peripheral.publish,
            daemon=True,
            name="robochess-gatt",
        )

        self._thread.start()
        self._published = True

    def stop(self) -> None:
        """Stop the GATT server and Bluetooth resources."""

        if self._peripheral and self._published:
            self._peripheral.mainloop.quit()
            self._peripheral.advert.stop()
            self._peripheral.app.stop()

            self._published = False
