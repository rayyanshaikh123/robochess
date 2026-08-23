from datetime import datetime, timezone
import re
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


def _to_object_id(value: str) -> Optional[ObjectId]:
    try:
        return ObjectId(value)
    except Exception:
        return None


async def get_many_by_ids(
    db: AsyncIOMotorDatabase, user_ids: list[str]
) -> dict[str, dict]:
    """Fetch several users at once, keyed by their string id.

    Malformed ids are skipped rather than raising, so one bad reference cannot
    take down a whole friends list.
    """
    object_ids = [oid for oid in (_to_object_id(u) for u in user_ids) if oid]
    if not object_ids:
        return {}
    cursor = db[USERS].find({"_id": {"$in": object_ids}})
    rows = await cursor.to_list(length=len(object_ids))
    return {str(row["_id"]): row for row in rows}


async def search_users(
    db: AsyncIOMotorDatabase, query: str, exclude_user_id: str, limit: int = 20
) -> list[dict]:
    """Find users by display-name prefix or exact email.

    Email must match exactly: allowing partial email search would let anyone
    enumerate addresses, so it only works when you already know the address.
    """
    term = query.strip()
    if not term:
        return []
    anchored = f"^{re.escape(term)}"
    exclude = _to_object_id(exclude_user_id)
    criteria: dict = {
        "$or": [
            {"display_name": {"$regex": anchored, "$options": "i"}},
            {"email": term.lower()},
        ]
    }
    if exclude is not None:
        criteria["_id"] = {"$ne": exclude}
    cursor = db[USERS].find(criteria).limit(max(1, min(limit, 50)))
    return await cursor.to_list(length=50)
