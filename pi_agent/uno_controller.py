"""Acknowledged JSON-lines protocol between Pi and Arduino Uno."""

from __future__ import annotations

from dataclasses import dataclass
import json
import time
import uuid
from typing import Protocol

import chess


class UnoError(RuntimeError):
    pass


class JsonLineTransport(Protocol):
    def write_line(self, message: dict) -> None: ...
    def read_line(self, timeout: float) -> dict | None: ...
    def close(self) -> None: ...


class SerialTransport:
    def __init__(self, port: str, baudrate: int) -> None:
        try:
            import serial
        except ImportError as exc:
            raise UnoError("Install pyserial to use a physical Uno") from exc
        self._serial = serial.Serial(port, baudrate, timeout=0.2)

    def write_line(self, message: dict) -> None:
        self._serial.write((json.dumps(message, separators=(",", ":")) + "\n").encode())
        self._serial.flush()

    def read_line(self, timeout: float) -> dict | None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            raw = self._serial.readline()
            if raw:
                try:
                    return json.loads(raw.decode("utf-8"))
                except json.JSONDecodeError:
                    continue
        return None

    def close(self) -> None:
        self._serial.close()


class SimulatedTransport:
    def __init__(self, fail: bool = False) -> None:
        self.pending: list[dict] = []
        self.fail = fail
    def write_line(self, message: dict) -> None:
        self.pending.append({"type": "error" if self.fail else "ack", "id": message["id"], "ok": not self.fail,
                             "error": "simulated failure" if self.fail else None})
    def read_line(self, _: float) -> dict | None:
        return self.pending.pop(0) if self.pending else None
    def close(self) -> None:
        return


@dataclass(frozen=True)
class MotionPlan:
    uci: str
    operations: list[dict]


def motion_plan(board: chess.Board, move: chess.Move) -> MotionPlan:
    """High-level physical actions; firmware owns calibrated XY coordinates."""
    if move not in board.legal_moves:
        raise UnoError(f"Cannot plan illegal move {move.uci()}")
    ops: list[dict] = []
    if board.is_en_passant(move):
        captured = chess.square(chess.square_file(move.to_square), chess.square_rank(move.from_square))
        ops.append({"op": "remove", "square": chess.square_name(captured)})
    elif board.is_capture(move):
        ops.append({"op": "remove", "square": chess.square_name(move.to_square)})
    ops.append({"op": "move", "from": chess.square_name(move.from_square), "to": chess.square_name(move.to_square)})
    if board.is_castling(move):
        rank, kingside = chess.square_rank(move.from_square), chess.square_file(move.to_square) > chess.square_file(move.from_square)
        rook_from = chess.square(7 if kingside else 0, rank)
        rook_to = chess.square(5 if kingside else 3, rank)
        ops.append({"op": "move", "from": chess.square_name(rook_from), "to": chess.square_name(rook_to)})
    if move.promotion:
        ops.append({"op": "promote", "square": chess.square_name(move.to_square), "piece": chess.piece_name(move.promotion)})
    return MotionPlan(move.uci(), ops)


class UnoController:
    def __init__(self, transport: JsonLineTransport, timeout: float = 8, retries: int = 1) -> None:
        self.transport, self.timeout, self.retries = transport, timeout, retries

    def execute(self, plan: MotionPlan) -> None:
        self.request("motion.execute", uci=plan.uci, operations=plan.operations)

    def request(self, command: str, **data: object) -> dict:
        request_id = str(uuid.uuid4())
        message = {"type": command, "id": request_id, **data}
        for _ in range(self.retries + 1):
            self.transport.write_line(message)
            response = self.transport.read_line(self.timeout)
            if response and response.get("id") == request_id and response.get("type") == "ack" and response.get("ok") is True:
                return response
        raise UnoError(f"Uno did not acknowledge {command}")

    def home(self) -> None:
        self.request("gantry.home")

    def status(self) -> dict:
        return self.request("gantry.status")

    def close(self) -> None:
        self.transport.close()
