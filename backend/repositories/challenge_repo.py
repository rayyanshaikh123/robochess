from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import CHALLENGES

PENDING = "pending"
ACCEPTED = "accepted"
REJECTED = "rejected"
CANCELLED = "cancelled"
EXPIRED = "expired"


def _to_object_id(value: str) -> Optional[ObjectId]:
    try:
        return ObjectId(value)
    except Exception:
        return None


async def create_challenge(
    db: AsyncIOMotorDatabase,
    challenger_id: str,
    challenged_id: str,
    time_control: Optional[dict],
    play_mode: str,
    challenger_surface: str,
    color_preference: str,
    expires_at: datetime,
) -> dict:
    now = datetime.now(timezone.utc)
    doc = {
        "challenger_id": challenger_id,
        "challenged_id": challenged_id,
        "status": PENDING,
        "time_control": time_control,
        "play_mode": play_mode,
        "challenger_surface": challenger_surface,
        "challenged_surface": None,
        "color_preference": color_preference,
        "game_id": None,
        "created_at": now,
        "updated_at": now,
        "expires_at": expires_at,
    }
    result = await db[CHALLENGES].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def get_by_id(db: AsyncIOMotorDatabase, challenge_id: str) -> Optional[dict]:
    object_id = _to_object_id(challenge_id)
    if object_id is None:
        return None
    return await db[CHALLENGES].find_one({"_id": object_id})


async def get_pending_between(
    db: AsyncIOMotorDatabase, challenger_id: str, challenged_id: str
) -> Optional[dict]:
    return await db[CHALLENGES].find_one(
        {
            "challenger_id": challenger_id,
            "challenged_id": challenged_id,
            "status": PENDING,
        }
    )


async def set_status(
    db: AsyncIOMotorDatabase,
    challenge_id: str,
    status: str,
    expected_status: str = PENDING,
) -> bool:
    """Compare-and-set the status.

    Accepting a challenge creates a game, so this guard is what makes a double
    accept impossible: only the first caller sees ``modified_count == 1``.
    """
    object_id = _to_object_id(challenge_id)
    if object_id is None:
        return False
    result = await db[CHALLENGES].update_one(
        {"_id": object_id, "status": expected_status},
        {"$set": {"status": status, "updated_at": datetime.now(timezone.utc)}},
    )
    return result.modified_count == 1


async def attach_game(
    db: AsyncIOMotorDatabase, challenge_id: str, game_id: str, challenged_surface: str
) -> bool:
    object_id = _to_object_id(challenge_id)
    if object_id is None:
        return False
    result = await db[CHALLENGES].update_one(
        {"_id": object_id},
        {
            "$set": {
                "game_id": game_id,
                "challenged_surface": challenged_surface,
                "updated_at": datetime.now(timezone.utc),
            }
        },
    )
    return result.modified_count == 1


async def list_for_user(
    db: AsyncIOMotorDatabase, user_id: str, incoming: bool, status: Optional[str] = None
) -> list[dict]:
    field = "challenged_id" if incoming else "challenger_id"
    query: dict = {field: user_id}
    if status is not None:
        query["status"] = status
    cursor = db[CHALLENGES].find(query).sort("created_at", -1)
    return await cursor.to_list(length=200)


async def expire_stale(db: AsyncIOMotorDatabase, now: Optional[datetime] = None) -> int:
    """Mark pending challenges past their deadline as expired.

    Rows are kept rather than TTL-deleted so a user can still see that a
    challenge lapsed instead of it silently vanishing.
    """
    moment = now or datetime.now(timezone.utc)
    result = await db[CHALLENGES].update_many(
        {"status": PENDING, "expires_at": {"$lte": moment}},
        {"$set": {"status": EXPIRED, "updated_at": moment}},
    )
    return result.modified_count
