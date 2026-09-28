from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.repositories.device_repo import list_by_user
from backend.db.collections import GAMES
from backend.repositories.puzzle_attempt_repo import (
    count_attempts,
    count_correct_attempts,
)
from backend.repositories.user_repo import count_users_with_rating_greater, get_by_id

_DRAW = "1/2-1/2"


def _outcome_for_user(game: dict, user_id: str) -> str | None:
    """'win' / 'loss' / 'draw' for this user, or None when it can't be attributed."""
    result = game.get("result")
    if not result:
        return None
    if result == _DRAW:
        return "draw"
    if game.get("user_players"):
        # Friend game: the winner is recorded by user id.
        return "win" if game.get("winner_id") == user_id else "loss"
    if (game.get("mode") or "human_vs_ai") != "human_vs_ai":
        return None  # pass-and-play: both sides are the same person
    white_won = result == "1-0"
    user_is_white = (game.get("player_side") or "white") == "white"
    return "win" if white_won == user_is_white else "loss"


async def get_user_stats(db: AsyncIOMotorDatabase, user_id: str) -> dict:
    user = await get_by_id(db, user_id)
    rating = int(user.get("rating", 1200)) if user else 1200
    higher_count = await count_users_with_rating_greater(db, rating)
    global_rank = higher_count + 1

    devices = await list_by_user(db, user_id)
    device_ids = [device.get("device_id") for device in devices if device.get("device_id")]

    # A user's games: solo games they started, games on their linked boards,
    # and friend games they took part in.
    ownership: list[dict] = [{"owner_user_id": user_id}, {"user_players": user_id}]
    if device_ids:
        ownership.append({"players": {"$in": device_ids}})
    query = {"$or": ownership}

    games_played = await db[GAMES].count_documents(query)
    outcomes = {"win": 0, "loss": 0, "draw": 0}
    finished = db[GAMES].find(
        {**query, "result": {"$nin": [None, ""]}},
        {"result": 1, "winner_id": 1, "user_players": 1, "mode": 1, "player_side": 1},
    )
    async for game in finished:
        outcome = _outcome_for_user(game, user_id)
        if outcome:
            outcomes[outcome] += 1
    wins, losses, draws = outcomes["win"], outcomes["loss"], outcomes["draw"]
    completed = wins + losses + draws
    win_rate = (wins / completed) if completed > 0 else 0.0

    attempts = await count_attempts(db, user_id)
    correct_attempts = await count_correct_attempts(db, user_id)
    accuracy = (correct_attempts / attempts) if attempts > 0 else 0.0

    return {
        "rating": rating,
        "global_rank": global_rank,
        "games_played": games_played,
        "wins": wins,
        "losses": losses,
        "draws": draws,
        "win_rate": win_rate,
        "accuracy": accuracy,
        "puzzle_attempts": attempts,
    }
