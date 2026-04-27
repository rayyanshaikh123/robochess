from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import REFRESH_TOKENS


async def insert_refresh_token(
    db: AsyncIOMotorDatabase,
    user_id: str,
    device_id: Optional[str],
    token_hash: str,
    expires_at,
) -> dict:
    now = datetime.now(timezone.utc)
    doc = {
        "user_id": ObjectId(user_id),
        "device_id": device_id,
        "token_hash": token_hash,
        "expires_at": expires_at,
        "revoked": False,
        "created_at": now,
    }
    result = await db[REFRESH_TOKENS].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def find_valid_refresh_token(db: AsyncIOMotorDatabase, token_hash: str) -> Optional[dict]:
    now = datetime.now(timezone.utc)
    return await db[REFRESH_TOKENS].find_one(
        {"token_hash": token_hash, "revoked": False, "expires_at": {"$gt": now}}
    )


async def revoke_refresh_token(db: AsyncIOMotorDatabase, token_hash: str) -> None:
    now = datetime.now(timezone.utc)
    await db[REFRESH_TOKENS].update_one(
        {"token_hash": token_hash},
        {"$set": {"revoked": True, "revoked_at": now}},
    )
