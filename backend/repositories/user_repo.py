from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import USERS


async def get_by_email(db: AsyncIOMotorDatabase, email: str) -> Optional[dict]:
    return await db[USERS].find_one({"email": email})


async def get_by_id(db: AsyncIOMotorDatabase, user_id: str) -> Optional[dict]:
    return await db[USERS].find_one({"_id": ObjectId(user_id)})


async def update_display_name(
    db: AsyncIOMotorDatabase, user_id: str, display_name: str
) -> Optional[dict]:
    await db[USERS].update_one(
        {"_id": ObjectId(user_id)},
        {"$set": {"display_name": display_name}},
    )
    return await get_by_id(db, user_id)


async def create_user(
    db: AsyncIOMotorDatabase,
    email: str,
    password_hash: str,
    display_name: str,
    is_guest: bool = False,
) -> dict:
    now = datetime.now(timezone.utc)
    doc = {
        "email": email,
        "password_hash": password_hash,
        "display_name": display_name,
        "is_guest": is_guest,
        "rating": 1200,
        "created_at": now,
    }
    result = await db[USERS].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def count_users_with_rating_greater(
    db: AsyncIOMotorDatabase, rating: int
) -> int:
    return await db[USERS].count_documents({"rating": {"$gt": rating}})
