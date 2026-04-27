from typing import Optional

import chess
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.repositories.puzzle_attempt_repo import insert_attempt
from backend.repositories.puzzle_repo import get_puzzle, list_puzzles


def _serialize_puzzle(puzzle: dict) -> dict:
    return {
        "puzzle_id": str(puzzle["_id"]),
        "fen": puzzle.get("fen"),
        "rating": puzzle.get("rating"),
        "tags": puzzle.get("tags", []),
        "length": len(puzzle.get("solution", [])),
    }


def _serialize_puzzle_detail(puzzle: dict) -> dict:
    data = _serialize_puzzle(puzzle)
    data["solution"] = puzzle.get("solution", [])
    return data


async def list_available_puzzles(
    db: AsyncIOMotorDatabase,
    limit: int = 20,
    rating_min: Optional[int] = None,
    rating_max: Optional[int] = None,
    tag: Optional[str] = None,
) -> list[dict]:
    puzzles = await list_puzzles(db, limit=limit, rating_min=rating_min, rating_max=rating_max, tag=tag)
    return [_serialize_puzzle(puzzle) for puzzle in puzzles]


async def get_puzzle_detail(
    db: AsyncIOMotorDatabase, puzzle_id: str
) -> tuple[Optional[dict], Optional[str]]:
    puzzle = await get_puzzle(db, puzzle_id)
    if not puzzle:
        return None, "Puzzle not found"
    return _serialize_puzzle_detail(puzzle), None


async def attempt_puzzle_move(
    db: AsyncIOMotorDatabase,
    puzzle_id: str,
    uci: str,
    move_index: int,
    user_id: Optional[str] = None,
) -> tuple[Optional[dict], Optional[str]]:
    puzzle = await get_puzzle(db, puzzle_id)
    if not puzzle:
        return None, "Puzzle not found"

    solution = puzzle.get("solution", [])
    if move_index < 0 or move_index >= len(solution):
        return None, "Invalid move index"

    try:
        board = chess.Board(puzzle.get("fen"))
    except Exception:
        return None, "Invalid puzzle state"

    for idx in range(move_index):
        expected = solution[idx]
        try:
            move = chess.Move.from_uci(expected)
        except Exception:
            return None, "Invalid puzzle solution"
        if move not in board.legal_moves:
            return None, "Invalid puzzle solution"
        board.push(move)

    try:
        attempt = chess.Move.from_uci(uci)
    except Exception:
        return None, "Invalid move format"

    if attempt not in board.legal_moves:
        return None, "Illegal move"

    correct = uci == solution[move_index]
    if correct:
        board.push(attempt)

    if user_id:
        try:
            await insert_attempt(db, user_id, puzzle_id, move_index, uci, correct)
        except Exception:
            pass

    return {
        "correct": correct,
        "next_fen": board.fen() if correct else board.fen(),
        "completed": correct and move_index == len(solution) - 1,
        "expected_uci": solution[move_index] if not correct else None,
        "next_index": move_index + (1 if correct else 0),
    }, None
