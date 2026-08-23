from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import FRIENDSHIPS

PENDING = "pending"
ACCEPTED = "accepted"
REJECTED = "rejected"


def _to_object_id(value: str) -> Optional[ObjectId]:
    try:
        return ObjectId(value)
    except Exception:
        return None


def pair_key(user_id: str, other_id: str) -> tuple[str, str]:
    """Order a pair so each friendship has exactly one representation.

    Storing the sorted pair is what lets a single unique index reject both a
    duplicate request and the mirrored one (B->A when A->B already exists).
    """
    return (user_id, other_id) if user_id <= other_id else (other_id, user_id)


async def get_between(
    db: AsyncIOMotorDatabase, user_id: str, other_id: str
) -> Optional[dict]:
    user_a, user_b = pair_key(user_id, other_id)
    return await db[FRIENDSHIPS].find_one({"user_a": user_a, "user_b": user_b})


async def get_by_id(db: AsyncIOMotorDatabase, friendship_id: str) -> Optional[dict]:
    object_id = _to_object_id(friendship_id)
    if object_id is None:
        return None
    return await db[FRIENDSHIPS].find_one({"_id": object_id})


async def create_friendship(
    db: AsyncIOMotorDatabase,
    requester_id: str,
    addressee_id: str,
    status: str = PENDING,
) -> dict:
    now = datetime.now(timezone.utc)
    user_a, user_b = pair_key(requester_id, addressee_id)
    doc = {
        "user_a": user_a,
        "user_b": user_b,
        "requester_id": requester_id,
        "addressee_id": addressee_id,
        "status": status,
        "created_at": now,
        "updated_at": now,
        "responded_at": now if status != PENDING else None,
    }
    result = await db[FRIENDSHIPS].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def set_status(
    db: AsyncIOMotorDatabase,
    friendship_id: str,
    status: str,
    expected_status: Optional[str] = None,
) -> bool:
    """Move a friendship to ``status``, optionally guarding on its current one."""
    object_id = _to_object_id(friendship_id)
    if object_id is None:
        return False
    query: dict = {"_id": object_id}
    if expected_status is not None:
        query["status"] = expected_status
    now = datetime.now(timezone.utc)
    result = await db[FRIENDSHIPS].update_one(
        query,
        {"$set": {"status": status, "updated_at": now, "responded_at": now}},
    )
    return result.modified_count == 1


async def reopen_request(
    db: AsyncIOMotorDatabase, friendship_id: str, requester_id: str, addressee_id: str
) -> bool:
    """Turn a previously rejected row back into a pending request.

    Re-using the row keeps the unique pair index satisfied while still letting
    someone ask again after a rejection.
    """
    object_id = _to_object_id(friendship_id)
    if object_id is None:
        return False
    now = datetime.now(timezone.utc)
    result = await db[FRIENDSHIPS].update_one(
        {"_id": object_id, "status": REJECTED},
        {
            "$set": {
                "status": PENDING,
                "requester_id": requester_id,
                "addressee_id": addressee_id,
                "updated_at": now,
                "responded_at": None,
            }
        },
    )
    return result.modified_count == 1


async def delete_friendship(db: AsyncIOMotorDatabase, friendship_id: str) -> bool:
    object_id = _to_object_id(friendship_id)
    if object_id is None:
        return False
    result = await db[FRIENDSHIPS].delete_one({"_id": object_id})
    return result.deleted_count == 1


async def list_by_status(
    db: AsyncIOMotorDatabase, user_id: str, status: str
) -> list[dict]:
    cursor = db[FRIENDSHIPS].find(
        {"status": status, "$or": [{"user_a": user_id}, {"user_b": user_id}]}
    ).sort("updated_at", -1)
    return await cursor.to_list(length=500)


async def list_requests(
    db: AsyncIOMotorDatabase, user_id: str, incoming: bool
) -> list[dict]:
    """Pending requests addressed to (incoming) or sent by (outgoing) a user."""
    field = "addressee_id" if incoming else "requester_id"
    cursor = db[FRIENDSHIPS].find({"status": PENDING, field: user_id}).sort(
        "created_at", -1
    )
    return await cursor.to_list(length=500)


async def statuses_for(
    db: AsyncIOMotorDatabase, user_id: str, other_ids: list[str]
) -> dict[str, dict]:
    """Relationship rows keyed by the *other* user id, for annotating search."""
    if not other_ids:
        return {}
    pairs = [
        {"user_a": a, "user_b": b} for a, b in (pair_key(user_id, o) for o in other_ids)
    ]
    cursor = db[FRIENDSHIPS].find({"$or": pairs})
    rows = await cursor.to_list(length=len(pairs))
    result: dict[str, dict] = {}
    for row in rows:
        other = row["user_b"] if row["user_a"] == user_id else row["user_a"]
        result[other] = row
    return result


async def are_friends(db: AsyncIOMotorDatabase, user_id: str, other_id: str) -> bool:
    row = await get_between(db, user_id, other_id)
    return bool(row and row.get("status") == ACCEPTED)
