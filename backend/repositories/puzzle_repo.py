from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import PUZZLES


def _to_object_id(puzzle_id: str) -> Optional[ObjectId]:
    try:
        return ObjectId(puzzle_id)
    except Exception:
        return None


async def create_puzzle(
    db: AsyncIOMotorDatabase,
    fen: str,
    solution: list[str],
    rating: Optional[int],
    tags: list[str],
) -> dict:
    now = datetime.now(timezone.utc)
    doc = {
        "fen": fen,
        "solution": solution,
        "rating": rating,
        "tags": tags,
        "created_at": now,
    }
    result = await db[PUZZLES].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def get_puzzle(db: AsyncIOMotorDatabase, puzzle_id: str) -> Optional[dict]:
    object_id = _to_object_id(puzzle_id)
    if object_id is None:
        return None
    return await db[PUZZLES].find_one({"_id": object_id})


async def list_puzzles(
    db: AsyncIOMotorDatabase,
    limit: int = 20,
    rating_min: Optional[int] = None,
    rating_max: Optional[int] = None,
    tag: Optional[str] = None,
) -> list[dict]:
    query: dict = {}
    if rating_min is not None or rating_max is not None:
        query["rating"] = {}
        if rating_min is not None:
            query["rating"]["$gte"] = rating_min
        if rating_max is not None:
            query["rating"]["$lte"] = rating_max
    if tag:
        query["tags"] = tag

    cursor = db[PUZZLES].find(query).sort("created_at", -1).limit(limit)
    return await cursor.to_list(length=limit)
