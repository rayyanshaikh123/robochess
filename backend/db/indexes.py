from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import BOARD_SESSION_CONFLICTS, BOARD_SESSIONS, DEVICES, GAMES, MOVES, PUZZLE_ATTEMPTS, REFRESH_TOKENS, USERS
from backend.db.collections import CHALLENGES, FRIENDSHIPS, GAME_CHATS, PUZZLES


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
    # Display name is searched case-insensitively by prefix; the plain index
    # still serves the anchored regex used by user search.
    await db[USERS].create_index("display_name")
    # One row per pair, with the pair stored sorted (user_a < user_b), so this
    # single constraint rejects duplicates AND reverse duplicates.
    await db[FRIENDSHIPS].create_index([("user_a", 1), ("user_b", 1)], unique=True)
    await db[FRIENDSHIPS].create_index([("user_a", 1), ("status", 1)])
    await db[FRIENDSHIPS].create_index([("user_b", 1), ("status", 1)])
    # Only one challenge may be pending between a given ordered pair; rejected
    # and cancelled rows stay for history, so the constraint is partial.
    await db[CHALLENGES].create_index(
        [("challenger_id", 1), ("challenged_id", 1)],
        unique=True,
        partialFilterExpression={"status": "pending"},
        name="challenges_unique_pending",
    )
    await db[CHALLENGES].create_index([("challenged_id", 1), ("status", 1)])
    await db[CHALLENGES].create_index([("challenger_id", 1), ("status", 1)])
    await db[CHALLENGES].create_index("expires_at")
    await db[GAMES].create_index("user_players")
    await db[GAMES].create_index([("user_players", 1), ("status", 1)])
    await db[GAME_CHATS].create_index([("game_id", 1), ("created_at", 1)])
