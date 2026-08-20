from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import BOARD_SESSION_CONFLICTS, BOARD_SESSIONS, DEVICES, GAMES, MOVES, PUZZLE_ATTEMPTS, REFRESH_TOKENS, USERS
from backend.db.collections import PUZZLES


async def ensure_indexes(db: AsyncIOMotorDatabase) -> None:
    await db[USERS].create_index("email", unique=True)
    await db[USERS].create_index("rating")
    await db[DEVICES].create_index("device_id", unique=True)
    await db[DEVICES].create_index("user_id")
    await db[DEVICES].create_index("pairing_code")
    await db[DEVICES].create_index("ble_pair_token")
    await db[GAMES].create_index("players")
    await db[GAMES].create_index("status")
    await db[GAMES].create_index("updated_at")
    await db[MOVES].create_index([("game_id", 1), ("move_number", 1)], unique=True)
    await db[REFRESH_TOKENS].create_index([("user_id", 1), ("device_id", 1)])
    await db[REFRESH_TOKENS].create_index("expires_at", expireAfterSeconds=0)
    await db[PUZZLES].create_index("rating")
    await db[PUZZLES].create_index("tags")
    await db[PUZZLE_ATTEMPTS].create_index("user_id")
    await db[PUZZLE_ATTEMPTS].create_index("puzzle_id")
    await db[PUZZLE_ATTEMPTS].create_index("created_at")
    await db[BOARD_SESSIONS].create_index([("device_id", 1), ("session_id", 1)], unique=True)
    await db[BOARD_SESSIONS].create_index("updated_at")
    await db[BOARD_SESSION_CONFLICTS].create_index([("device_id", 1), ("session_id", 1), ("created_at", -1)])
