"""Offline RoboChess BLE protocol primitives.

The Pi is authoritative. This module deliberately contains no chess rules; it
validates transport envelopes and delegates commands to the board controller.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Callable
from uuid import uuid4

PROTOCOL_VERSION = 1


class ProtocolError(ValueError):
    pass


@dataclass(frozen=True)
class Message:
    type: str
    version: int = PROTOCOL_VERSION
    seq: int | None = None
    request_id: str | None = None
    payload: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        value = {
            "version": self.version,
            "type": self.type,
            **({"seq": self.seq} if self.seq is not None else {}),
            **({"id": self.request_id} if self.request_id else {}),
        }
        value.update(self.payload or {})
        return value

    def encode(self) -> bytes:
        return json.dumps(self.to_dict(), separators=(",", ":")).encode("utf-8")

    @classmethod
    def decode(cls, raw: bytes | str) -> "Message":
        try:
            value = json.loads(raw)
        except (TypeError, json.JSONDecodeError) as exc:
            raise ProtocolError("malformed JSON") from exc
        if not isinstance(value, dict) or not isinstance(value.get("version"), int):
            raise ProtocolError("version is required")
        if value["version"] != PROTOCOL_VERSION:
            raise ProtocolError(f"unsupported protocol version: {value['version']}")
        if not isinstance(value.get("type"), str) or not value["type"]:
            raise ProtocolError("type is required")
        seq = value.get("seq")
        if seq is not None and (not isinstance(seq, int) or seq < 1):
            raise ProtocolError("seq must be a positive integer")
        payload = dict(value)
        for key in ("version", "type", "seq", "id"):
            payload.pop(key, None)
        return cls(value["type"], value["version"], seq, value.get("id"), payload)


class SessionProtocol:
    """Idempotent command gate for a single authorized BLE client."""

    def __init__(self, handler: Callable[[Message], Message]) -> None:
        self.handler = handler
        self.last_seq = 0
        self._responses: dict[str, Message] = {}

    def handle(self, raw: bytes | str) -> bytes:
        try:
            message = Message.decode(raw)
            if message.request_id and message.request_id in self._responses:
                return self._responses[message.request_id].encode()
            if message.seq is not None and message.seq <= self.last_seq:
                raise ProtocolError("out-of-order or duplicate sequence")
            if message.seq is not None:
                self.last_seq = message.seq
            response = self.handler(message)
            if message.request_id:
                self._responses[message.request_id] = response
            return response.encode()
        except ProtocolError as exc:
            return Message("error", payload={"reason": str(exc)}).encode()


def command(message_type: str, seq: int, **payload: Any) -> Message:
    return Message(message_type, seq=seq, request_id=str(uuid4()), payload=payload)
