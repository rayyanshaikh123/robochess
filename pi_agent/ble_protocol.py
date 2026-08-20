"""Wire format and UUIDs for RoboChess BLE provisioning.

BLE writes are JSON envelopes. Large payloads are split into numbered chunks
and reassembled by the receiver before decoding.
"""

import json
import uuid
import base64
from typing import Any

SERVICE_UUID = "0000f00d-0000-1000-8000-00805f9b34fb"
DEVICE_INFO_UUID = "0000f00e-0000-1000-8000-00805f9b34fb"
CONTROL_UUID = "0000f00f-0000-1000-8000-00805f9b34fb"
WIFI_UUID = "0000f010-0000-1000-8000-00805f9b34fb"
STATUS_UUID = "0000f011-0000-1000-8000-00805f9b34fb"
PROTOCOL_VERSION = "1"
MAX_CHUNK_BYTES = 180
# A chunk frame has UUID metadata. 42 raw bytes stays below 180 bytes after
# base64 encoding, even with a 36-character request ID and device ID.
CHUNK_PAYLOAD_BYTES = 42


def envelope(message_type: str, device_id: str, **data: Any) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "request_id": str(uuid.uuid4()),
        "type": message_type,
        "device_id": device_id,
        "data": data,
    }


def encode_chunks(message: dict[str, Any]) -> list[bytes]:
    raw = json.dumps(message, separators=(",", ":")).encode("utf-8")
    if len(raw) <= MAX_CHUNK_BYTES:
        return [raw]
    pieces = [raw[offset:offset + CHUNK_PAYLOAD_BYTES] for offset in range(0, len(raw), CHUNK_PAYLOAD_BYTES)]
    request_id = str(message.get("request_id") or uuid.uuid4())
    device_id = str(message.get("device_id", ""))
    return [
        json.dumps(
            {
                "v": PROTOCOL_VERSION, "t": "chunk", "id": request_id,
                "d": device_id, "i": index, "n": len(pieces),
                "p": base64.b64encode(piece).decode("ascii"),
            }, separators=(",", ":"),
        ).encode("utf-8")
        for index, piece in enumerate(pieces)
    ]


def decode_chunk(frame: bytes | str) -> tuple[str, int, int, bytes] | None:
    """Return a framed output chunk or None for an ordinary message."""
    try:
        value = json.loads(frame.decode("utf-8") if isinstance(frame, bytes) else frame)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict) or value.get("t") != "chunk" or value.get("v") != PROTOCOL_VERSION:
        return None
    try:
        return str(value["id"]), int(value["i"]), int(value["n"]), base64.b64decode(value["p"], validate=True)
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("Invalid RoboChess BLE chunk") from exc


def decode_message(raw: bytes | str) -> dict[str, Any]:
    message = json.loads(raw.decode("utf-8") if isinstance(raw, bytes) else raw)
    if not isinstance(message, dict) or message.get("version") != PROTOCOL_VERSION:
        raise ValueError("Unsupported RoboChess BLE protocol")
    return message


GAME_MESSAGE_TYPES = {
    "session.start", "session.reset", "session.resume", "state.request", "move.propose",
    "gantry.home", "gantry.status",
}


def validate_game_message(message: dict[str, Any]) -> None:
    if message.get("type") not in GAME_MESSAGE_TYPES:
        raise ValueError("Unsupported game message")
    data = message.get("data")
    if not isinstance(data, dict):
        raise ValueError("Game message data must be an object")
    if message["type"] == "move.propose" and not isinstance(data.get("uci"), str):
        raise ValueError("move.propose requires a UCI move")
    if "client_seq" in data and (not isinstance(data["client_seq"], int) or data["client_seq"] < 0):
        raise ValueError("client_seq must be a non-negative integer")
