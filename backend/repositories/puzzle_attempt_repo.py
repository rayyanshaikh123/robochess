from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import PUZZLE_ATTEMPTS


def _to_object_id(value: str) -> Optional[ObjectId]:
    try:
        return ObjectId(value)
    except Exception:
        return None


async def insert_attempt(
    db: AsyncIOMotorDatabase,
    user_id: str,
    puzzle_id: str,
    move_index: int,
    uci: str,
    correct: bool,
) -> dict:
    now = datetime.now(timezone.utc)
    user_object_id = _to_object_id(user_id)
    doc = {
        "user_id": user_object_id if user_object_id else user_id,
        "puzzle_id": puzzle_id,
        "move_index": move_index,
        "uci": uci,
        "correct": correct,
        "created_at": now,
    }
    result = await db[PUZZLE_ATTEMPTS].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def count_attempts(db: AsyncIOMotorDatabase, user_id: str) -> int:
    user_object_id = _to_object_id(user_id)
    query = {"user_id": user_object_id if user_object_id else user_id}
    return await db[PUZZLE_ATTEMPTS].count_documents(query)


async def count_correct_attempts(db: AsyncIOMotorDatabase, user_id: str) -> int:
    user_object_id = _to_object_id(user_id)
    query = {"user_id": user_object_id if user_object_id else user_id, "correct": True}
    return await db[PUZZLE_ATTEMPTS].count_documents(query)
