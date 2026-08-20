"""Idempotent persistence for Pi-authoritative offline board sessions."""

from __future__ import annotations

import chess
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.repositories.board_session_repo import create_conflict, create_session, get_session, replace_session


def _validated_fen(initial_fen: str, moves: list[str]) -> str:
    board = chess.Board(initial_fen)
    for uci in moves:
        move = chess.Move.from_uci(uci)
        if move not in board.legal_moves:
            raise ValueError(f"Illegal session move: {uci}")
        board.push(move)
    return board.fen()


async def sync_board_session(db: "AsyncIOMotorDatabase", device_id: str, payload: dict) -> tuple[dict | None, str | None]:
    try:
        final_fen = _validated_fen(payload["initial_fen"], payload["moves"])
    except (ValueError, TypeError) as exc:
        return None, str(exc)
    if payload["version"] != len(payload["moves"]):
        return None, "Session version must equal move count"
    if payload.get("fen") and payload["fen"] != final_fen:
        return None, "Session FEN does not match move history"
    incoming = {"device_id": device_id, "session_id": payload["session_id"], "initial_fen": payload["initial_fen"], "moves": payload["moves"], "version": payload["version"], "state_hash": payload["state_hash"], "fen": final_fen, "phase": payload.get("phase"), "game_over": payload.get("game_over", False), "result": payload.get("result")}
    existing = await get_session(db, device_id, incoming["session_id"])
    if existing is None:
        await create_session(db, incoming)
        return {"sync_status": "created", **incoming}, None
    if existing.get("state_hash") == incoming["state_hash"]:
        return {"sync_status": "unchanged", "session_id": incoming["session_id"], "version": incoming["version"]}, None
    existing_moves = existing.get("moves", [])
    if incoming["moves"][:len(existing_moves)] == existing_moves and incoming["version"] > int(existing.get("version", 0)):
        await replace_session(db, device_id, incoming["session_id"], incoming)
        return {"sync_status": "updated", "session_id": incoming["session_id"], "version": incoming["version"]}, None
    await create_conflict(db, {"device_id": device_id, "session_id": incoming["session_id"], "existing": {"state_hash": existing.get("state_hash"), "moves": existing_moves}, "incoming": incoming})
    return {"sync_status": "conflict", "session_id": incoming["session_id"], "version": existing.get("version")}, None
