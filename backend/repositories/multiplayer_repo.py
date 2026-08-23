from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import GAME_CHATS, GAMES


def _to_object_id(value: str) -> Optional[ObjectId]:
    try:
        return ObjectId(value)
    except Exception:
        return None


async def create_multiplayer_game(
    db: AsyncIOMotorDatabase,
    user_players: list[str],
    colors: dict,
    surfaces: dict,
    play_mode: str,
    current_fen: str,
    time_control: Optional[dict] = None,
    clocks: Optional[dict] = None,
    rematch_of: Optional[str] = None,
) -> dict:
    """Create a friend game.

    The legacy ``players`` list is left empty on purpose: it holds *device* ids
    everywhere else (user_stats counts games with it), so participants live in
    the new ``user_players`` field instead of overloading it.
    """
    now = datetime.now(timezone.utc)
    doc = {
        "players": [],
        "user_players": user_players,
        "colors": colors,
        "surfaces": surfaces,
        "play_mode": play_mode,
        "current_fen": current_fen,
        "status": "active",
        "game_version": 0,
        "last_move": None,
        "result": None,
        "winner_id": None,
        "end_reason": None,
        "draw_offer_by": None,
        "time_control": time_control,
        "clocks": clocks,
        "rematch_of": rematch_of,
        "created_at": now,
        "updated_at": now,
    }
    result = await db[GAMES].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def get_game(db: AsyncIOMotorDatabase, game_id: str) -> Optional[dict]:
    object_id = _to_object_id(game_id)
    if object_id is None:
        return None
    return await db[GAMES].find_one({"_id": object_id})


async def list_for_user(
    db: AsyncIOMotorDatabase, user_id: str, statuses: Optional[list[str]] = None
) -> list[dict]:
    query: dict = {"user_players": user_id}
    if statuses:
        query["status"] = {"$in": statuses}
    cursor = db[GAMES].find(query).sort("updated_at", -1)
    return await cursor.to_list(length=200)


async def finish_game(
    db: AsyncIOMotorDatabase,
    game_id: str,
    result: str,
    winner_id: Optional[str],
    end_reason: str,
) -> bool:
    """Close a game out. Guarded on ``status`` so it can only happen once."""
    object_id = _to_object_id(game_id)
    if object_id is None:
        return False
    updated = await db[GAMES].update_one(
        {"_id": object_id, "status": "active"},
        {
            "$set": {
                "status": "completed",
                "result": result,
                "winner_id": winner_id,
                "end_reason": end_reason,
                "draw_offer_by": None,
                "updated_at": datetime.now(timezone.utc),
            }
        },
    )
    return updated.modified_count == 1


async def set_draw_offer(
    db: AsyncIOMotorDatabase, game_id: str, user_id: Optional[str]
) -> bool:
    object_id = _to_object_id(game_id)
    if object_id is None:
        return False
    updated = await db[GAMES].update_one(
        {"_id": object_id, "status": "active"},
        {"$set": {"draw_offer_by": user_id, "updated_at": datetime.now(timezone.utc)}},
    )
    return updated.modified_count == 1


async def set_turn_started(
    db: AsyncIOMotorDatabase, game_id: str, moment: datetime
) -> bool:
    """Stamp when the side to move started thinking; clocks bill from this."""
    object_id = _to_object_id(game_id)
    if object_id is None:
        return False
    updated = await db[GAMES].update_one(
        {"_id": object_id}, {"$set": {"turn_started_at": moment}}
    )
    return updated.modified_count == 1


async def update_clocks(db: AsyncIOMotorDatabase, game_id: str, clocks: dict) -> bool:
    object_id = _to_object_id(game_id)
    if object_id is None:
        return False
    updated = await db[GAMES].update_one(
        {"_id": object_id},
        {"$set": {"clocks": clocks, "updated_at": datetime.now(timezone.utc)}},
    )
    return updated.modified_count == 1


async def add_chat(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str, text: str
) -> dict:
    doc = {
        "game_id": game_id,
        "user_id": user_id,
        "text": text,
        "created_at": datetime.now(timezone.utc),
    }
    result = await db[GAME_CHATS].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def list_chat(db: AsyncIOMotorDatabase, game_id: str) -> list[dict]:
    cursor = db[GAME_CHATS].find({"game_id": game_id}).sort("created_at", 1)
    return await cursor.to_list(length=500)
