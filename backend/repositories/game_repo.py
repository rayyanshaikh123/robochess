from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import GAMES


def _to_object_id(game_id: str) -> Optional[ObjectId]:
    try:
        return ObjectId(game_id)
    except Exception:
        return None


async def create_game(
    db: AsyncIOMotorDatabase,
    players: list[str],
    current_fen: str,
    status: str,
    session=None,
) -> dict:
    now = datetime.now(timezone.utc)
    doc = {
        "players": players,
        "current_fen": current_fen,
        "status": status,
        "game_version": 0,
        "last_move": None,
        "created_at": now,
        "updated_at": now,
    }
    result = await db[GAMES].insert_one(doc, session=session)
    doc["_id"] = result.inserted_id
    return doc


async def get_game(db: AsyncIOMotorDatabase, game_id: str, session=None) -> Optional[dict]:
    object_id = _to_object_id(game_id)
    if object_id is None:
        return None
    return await db[GAMES].find_one({"_id": object_id}, session=session)


async def update_game_state(
    db: AsyncIOMotorDatabase,
    game_id: str,
    expected_version: int,
    current_fen: str,
    last_move: str,
    session=None,
) -> bool:
    object_id = _to_object_id(game_id)
    if object_id is None:
        return False

    now = datetime.now(timezone.utc)
    result = await db[GAMES].update_one(
        {"_id": object_id, "game_version": expected_version},
        {
            "$set": {"current_fen": current_fen, "last_move": last_move, "updated_at": now},
            "$inc": {"game_version": 1},
        },
        session=session,
    )
    return result.modified_count == 1


async def update_game_status(
    db: AsyncIOMotorDatabase, game_id: str, status: str, session=None
) -> bool:
    object_id = _to_object_id(game_id)
    if object_id is None:
        return False
    now = datetime.now(timezone.utc)
    result = await db[GAMES].update_one(
        {"_id": object_id},
        {"$set": {"status": status, "updated_at": now}},
        session=session,
    )
    return result.modified_count == 1


async def count_games_by_players(
    db: AsyncIOMotorDatabase, player_ids: list[str]
) -> int:
    if not player_ids:
        return 0
    return await db[GAMES].count_documents({"players": {"$in": player_ids}})


async def count_games_by_players_and_status(
    db: AsyncIOMotorDatabase, player_ids: list[str], statuses: list[str]
) -> int:
    if not player_ids or not statuses:
        return 0
    return await db[GAMES].count_documents(
        {"players": {"$in": player_ids}, "status": {"$in": statuses}}
    )
