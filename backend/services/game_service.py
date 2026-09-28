from typing import Optional

import chess

from motor.motor_asyncio import AsyncIOMotorDatabase
from pymongo.errors import DuplicateKeyError

from backend.repositories.game_repo import create_game as repo_create_game
from backend.repositories.game_repo import (
    finish_game,
    get_game,
    update_game_state,
    update_game_status,
)
from backend.repositories.move_repo import get_moves_after, insert_move


def _serialize_game(game: dict) -> dict:
    return {
        "game_id": str(game["_id"]),
        "current_fen": game.get("current_fen"),
        "status": game.get("status"),
        "game_version": game.get("game_version", 0),
        "last_move": game.get("last_move"),
        "result": game.get("result"),
        "mode": game.get("mode"),
        "difficulty": game.get("difficulty"),
        "player_side": game.get("player_side"),
    }


def _serialize_move(move: dict) -> dict:
    created_at = move.get("created_at")
    if hasattr(created_at, "isoformat"):
        created_at = created_at.isoformat()
        
    return {
        "move_number": move.get("move_number"),
        "uci": move.get("uci"),
        "fen_after": move.get("fen_after"),
        "created_at": created_at,
    }


async def create_game(
    db: AsyncIOMotorDatabase,
    current_fen: str,
    players: Optional[list[str]] = None,
    mode: str = "human_vs_ai",
    difficulty: int = 5,
    player_side: str = "white",
    owner_user_id: Optional[str] = None,
) -> dict:
    # Per-game settings live on the document so the AI never depends on
    # process-wide state shared between players.
    settings = {
        "mode": mode,
        "difficulty": difficulty,
        "player_side": player_side,
        "uses_board": bool(players),
        # Who the game counts for in stats (solo games have no user in ``players``).
        "owner_user_id": owner_user_id,
    }
    game = await repo_create_game(db, players or [], current_fen, "active", settings=settings)
    return _serialize_game(game)


async def get_game_state(
    db: AsyncIOMotorDatabase, game_id: str
) -> tuple[Optional[dict], Optional[str]]:
    game = await get_game(db, game_id)
    if not game:
        return None, "Game not found"
    return _serialize_game(game), None


async def record_move(
    db: AsyncIOMotorDatabase,
    game_id: str,
    uci: str,
    fen_after: str,
    expected_version: Optional[int] = None,
) -> tuple[Optional[dict], Optional[str]]:
    # Standalone MongoDB does not support transactions. 
    # Use Optimistic Concurrency Control (OCC) via the version field.
    game = await get_game(db, game_id)
    if not game:
        return None, "Game not found"

    current_version = int(game.get("game_version", 0))
    if expected_version is not None and current_version != expected_version:
        return None, f"Version mismatch: expected {expected_version}, got {current_version}"

    move_number = current_version + 1
    
    # 1. Insert move history
    try:
        await insert_move(
            db,
            game_id,
            move_number,
            uci,
            fen_after,
        )
    except DuplicateKeyError:
        return None, "Duplicate move"

    # 2. Update game state atomically using version check
    updated = await update_game_state(
        db,
        game_id,
        expected_version=current_version,
        current_fen=fen_after,
        last_move=uci,
    )
    
    if not updated:
        # Note: In a production environment with transactions, this would roll back.
        # Here, the move is already inserted. For dev purposes, this is acceptable
        # as the version check prevents corrupted game states.
        return None, "Version conflict (someone else moved first)"

    # Close the game out when this move ended it (checkmate, stalemate, ...).
    outcome = chess.Board(fen_after).outcome()
    if outcome is not None:
        await finish_game(
            db, game_id, "completed", outcome.result(), outcome.termination.name.lower()
        )

    # Fetch fresh game state
    game = await get_game(db, game_id)
    if not game:
        return None, "Game not found after update"
    return _serialize_game(game), None


async def validate_and_record_move(
    db: AsyncIOMotorDatabase,
    game_id: str,
    uci: str,
    expected_version: Optional[int] = None,
) -> tuple[Optional[dict], Optional[str]]:
    game = await get_game(db, game_id)
    if not game:
        return None, "Game not found"
    if game.get("status", "active") != "active":
        return None, "Game is over"

    try:
        board = chess.Board(game.get("current_fen"))
        move = chess.Move.from_uci(uci)
    except Exception:
        return None, "Invalid move format"

    if move not in board.legal_moves:
        return None, "Illegal move"

    board.push(move)
    fen_after = board.fen()
    version = expected_version if expected_version is not None else int(game.get("game_version", 0))
    return await record_move(db, game_id, uci, fen_after, expected_version=version)


async def end_game(
    db: AsyncIOMotorDatabase, game_id: str, status: str
) -> tuple[bool, Optional[str]]:
    updated = await update_game_status(db, game_id, status)
    if not updated:
        return False, "Game not found"
    return True, None


async def resign_game(
    db: AsyncIOMotorDatabase, game_id: str
) -> tuple[bool, Optional[str]]:
    """Resign a solo or board game on behalf of the human player."""
    game = await get_game(db, game_id)
    if not game:
        return False, "Game not found"
    if (game.get("mode") or "human_vs_ai") == "human_vs_ai":
        loser_is_white = (game.get("player_side") or "white") == "white"
    else:
        # Pass-and-play: the side to move is the one resigning.
        loser_is_white = chess.Board(game.get("current_fen")).turn == chess.WHITE
    result = "0-1" if loser_is_white else "1-0"
    if not await finish_game(db, game_id, "resigned", result, "resignation"):
        return False, "Game is already over"
    return True, None


async def get_moves_since(
    db: AsyncIOMotorDatabase, game_id: str, move_number: int
) -> list[dict]:
    moves = await get_moves_after(db, game_id, move_number)
    return [_serialize_move(move) for move in moves]
