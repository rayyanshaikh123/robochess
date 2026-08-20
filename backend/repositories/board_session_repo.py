from datetime import datetime, timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import BOARD_SESSION_CONFLICTS, BOARD_SESSIONS


async def get_session(db: "AsyncIOMotorDatabase", device_id: str, session_id: str) -> dict | None:
    return await db[BOARD_SESSIONS].find_one({"device_id": device_id, "session_id": session_id})


async def create_session(db: "AsyncIOMotorDatabase", document: dict) -> dict:
    now = datetime.now(timezone.utc)
    document.update({"created_at": now, "updated_at": now})
    await db[BOARD_SESSIONS].insert_one(document)
    return document


async def replace_session(db: "AsyncIOMotorDatabase", device_id: str, session_id: str, document: dict) -> None:
    document["updated_at"] = datetime.now(timezone.utc)
    await db[BOARD_SESSIONS].update_one({"device_id": device_id, "session_id": session_id}, {"$set": document})


async def create_conflict(db: "AsyncIOMotorDatabase", document: dict) -> None:
    document["created_at"] = datetime.now(timezone.utc)
    await db[BOARD_SESSION_CONFLICTS].insert_one(document)
