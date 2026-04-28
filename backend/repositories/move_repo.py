from datetime import datetime, timezone

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import MOVES


def _to_object_id(game_id: str) -> ObjectId:
    return ObjectId(game_id)


async def insert_move(
    db: AsyncIOMotorDatabase,
    game_id: str,
    move_number: int,
    uci: str,
    fen_after: str,
    session=None,
) -> dict:
    now = datetime.now(timezone.utc)
    doc = {
        "game_id": _to_object_id(game_id),
        "move_number": move_number,
        "uci": uci,
        "fen_after": fen_after,
        "created_at": now,
    }
    result = await db[MOVES].insert_one(doc, session=session)
    doc["_id"] = result.inserted_id
    return doc


async def get_moves_after(
    db: AsyncIOMotorDatabase, game_id: str, move_number: int
) -> list[dict]:
    cursor = db[MOVES].find(
        {"game_id": _to_object_id(game_id), "move_number": {"$gt": move_number}}
    ).sort("move_number", 1)
    return await cursor.to_list(length=2000)


async def get_all_moves(
    db: AsyncIOMotorDatabase, game_id: str
) -> list[dict]:
    """Return every move for *game_id* ordered by move_number ascending."""
    cursor = db[MOVES].find(
        {"game_id": _to_object_id(game_id)}
    ).sort("move_number", 1)
    return await cursor.to_list(length=2000)
