from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.repositories.device_repo import list_by_user
from backend.repositories.game_repo import (
    count_games_by_players,
    count_games_by_players_and_status,
)
from backend.repositories.puzzle_attempt_repo import (
    count_attempts,
    count_correct_attempts,
)
from backend.repositories.user_repo import count_users_with_rating_greater, get_by_id

_WIN_STATUSES = ["won", "win", "victory"]
_LOSS_STATUSES = ["lost", "loss", "defeat"]
_DRAW_STATUSES = ["draw", "drawn", "stalemate"]


async def get_user_stats(db: AsyncIOMotorDatabase, user_id: str) -> dict:
    user = await get_by_id(db, user_id)
    rating = int(user.get("rating", 1200)) if user else 1200
    higher_count = await count_users_with_rating_greater(db, rating)
    global_rank = higher_count + 1

    devices = await list_by_user(db, user_id)
    device_ids = [device.get("device_id") for device in devices if device.get("device_id")]

    games_played = await count_games_by_players(db, device_ids)
    wins = await count_games_by_players_and_status(db, device_ids, _WIN_STATUSES)
    losses = await count_games_by_players_and_status(db, device_ids, _LOSS_STATUSES)
    draws = await count_games_by_players_and_status(db, device_ids, _DRAW_STATUSES)
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
