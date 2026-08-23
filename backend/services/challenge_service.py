"""Game challenges between friends.

Accepting is the only path that creates a multiplayer game. The status
compare-and-set in :func:`accept_challenge` is what guarantees a challenge can
produce exactly one game even if two accepts race.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from motor.motor_asyncio import AsyncIOMotorDatabase
from pymongo.errors import DuplicateKeyError

from backend.repositories.challenge_repo import (
    ACCEPTED,
    CANCELLED,
    EXPIRED,
    PENDING,
    REJECTED,
    attach_game,
    create_challenge,
    expire_stale,
    get_by_id,
    get_pending_between,
    list_for_user,
    set_status,
)
from backend.repositories.friendship_repo import are_friends
from backend.repositories.multiplayer_repo import get_game
from backend.repositories.user_repo import get_many_by_ids
from backend.services.multiplayer_service import (
    SURFACE_APP,
    create_game_for_players,
    resolve_time_control,
    serialize_game,
)

CHALLENGE_TTL_MINUTES = 10
VALID_COLOR_PREFERENCES = {"white", "black", "random"}


def _iso(value) -> Optional[str]:
    return value.isoformat() if hasattr(value, "isoformat") else None


def _serialize(challenge: dict, user_id: str, profiles: Optional[dict] = None) -> dict:
    challenger_id = challenge.get("challenger_id")
    challenged_id = challenge.get("challenged_id")
    other_id = challenged_id if challenger_id == user_id else challenger_id
    profile = (profiles or {}).get(other_id) or {}
    return {
        "challenge_id": str(challenge["_id"]),
        "status": challenge.get("status"),
        "outgoing": challenger_id == user_id,
        "opponent": {
            "user_id": other_id or "",
            "display_name": profile.get("display_name") or "Player",
            "rating": profile.get("rating"),
        },
        "time_control": challenge.get("time_control"),
        "play_mode": challenge.get("play_mode"),
        "color_preference": challenge.get("color_preference"),
        "game_id": challenge.get("game_id"),
        "created_at": _iso(challenge.get("created_at")),
        "expires_at": _iso(challenge.get("expires_at")),
    }


async def _hydrate(db, rows: list[dict], user_id: str) -> list[dict]:
    others = [
        row.get("challenged_id") if row.get("challenger_id") == user_id
        else row.get("challenger_id")
        for row in rows
    ]
    profiles = await get_many_by_ids(db, [o for o in others if o])
    return [_serialize(row, user_id, profiles) for row in rows]


async def create(
    db: AsyncIOMotorDatabase,
    user_id: str,
    opponent_id: str,
    time_control_key: Optional[str] = None,
    surface: str = SURFACE_APP,
    color_preference: str = "random",
) -> tuple[Optional[dict], Optional[str]]:
    if not opponent_id:
        return None, "Opponent is required"
    if opponent_id == user_id:
        return None, "You cannot challenge yourself"
    if color_preference not in VALID_COLOR_PREFERENCES:
        return None, "Invalid colour preference"

    time_control, tc_error = resolve_time_control(time_control_key)
    if tc_error:
        return None, tc_error

    if not await are_friends(db, user_id, opponent_id):
        return None, "You can only challenge friends"

    await expire_stale(db)
    if await get_pending_between(db, user_id, opponent_id):
        return None, "You already have a pending challenge with this player"

    expires_at = datetime.now(timezone.utc) + timedelta(minutes=CHALLENGE_TTL_MINUTES)
    try:
        row = await create_challenge(
            db,
            challenger_id=user_id,
            challenged_id=opponent_id,
            time_control=time_control,
            play_mode=None,
            challenger_surface=surface,
            color_preference=color_preference,
            expires_at=expires_at,
        )
    except DuplicateKeyError:
        # The partial unique index caught a second rapid challenge.
        return None, "You already have a pending challenge with this player"

    profiles = await get_many_by_ids(db, [opponent_id])
    return _serialize(row, user_id, profiles), None


async def accept(
    db: AsyncIOMotorDatabase,
    user_id: str,
    challenge_id: str,
    surface: str = SURFACE_APP,
) -> tuple[Optional[dict], Optional[str]]:
    challenge = await get_by_id(db, challenge_id)
    if challenge is None:
        return None, "Challenge not found"
    if challenge.get("challenged_id") != user_id:
        return None, "Not authorized"
    if challenge.get("status") != PENDING:
        return None, "Challenge is no longer pending"

    expires_at = challenge.get("expires_at")
    if isinstance(expires_at, datetime):
        deadline = expires_at if expires_at.tzinfo else expires_at.replace(tzinfo=timezone.utc)
        if deadline <= datetime.now(timezone.utc):
            await set_status(db, challenge_id, EXPIRED, expected_status=PENDING)
            return None, "Challenge has expired"

    # Claim the challenge first; whoever wins this CAS creates the only game.
    if not await set_status(db, challenge_id, ACCEPTED, expected_status=PENDING):
        return None, "Challenge is no longer pending"

    challenger_id = challenge.get("challenger_id")
    game = await create_game_for_players(
        db,
        challenger_id=challenger_id,
        challenged_id=user_id,
        time_control=challenge.get("time_control"),
        challenger_surface=challenge.get("challenger_surface") or SURFACE_APP,
        challenged_surface=surface,
        color_preference=challenge.get("color_preference") or "random",
    )
    game_id = str(game["_id"])
    await attach_game(db, challenge_id, game_id, surface)

    profiles = await get_many_by_ids(db, [challenger_id, user_id])
    return {
        "challenge_id": challenge_id,
        "game_id": game_id,
        "game": serialize_game(game, user_id, profiles),
        "challenger_id": challenger_id,
        "challenged_id": user_id,
    }, None


async def reject(
    db: AsyncIOMotorDatabase, user_id: str, challenge_id: str
) -> tuple[Optional[dict], Optional[str]]:
    challenge = await get_by_id(db, challenge_id)
    if challenge is None:
        return None, "Challenge not found"
    if challenge.get("challenged_id") != user_id:
        return None, "Not authorized"
    if not await set_status(db, challenge_id, REJECTED, expected_status=PENDING):
        return None, "Challenge is no longer pending"
    return {"challenge_id": challenge_id, "status": REJECTED,
            "challenger_id": challenge.get("challenger_id")}, None


async def cancel(
    db: AsyncIOMotorDatabase, user_id: str, challenge_id: str
) -> tuple[Optional[dict], Optional[str]]:
    challenge = await get_by_id(db, challenge_id)
    if challenge is None:
        return None, "Challenge not found"
    if challenge.get("challenger_id") != user_id:
        return None, "Not authorized"
    if not await set_status(db, challenge_id, CANCELLED, expected_status=PENDING):
        return None, "Challenge is no longer pending"
    return {"challenge_id": challenge_id, "status": CANCELLED,
            "challenged_id": challenge.get("challenged_id")}, None


async def create_rematch(
    db: AsyncIOMotorDatabase, user_id: str, game_id: str
) -> tuple[Optional[dict], Optional[str]]:
    """Offer a rematch of a finished game, with colours swapped.

    This goes through the normal challenge lifecycle so the opponent still has
    to agree, and all the usual guards (friendship, duplicates) apply.
    """
    game = await get_game(db, game_id)
    if game is None:
        return None, "Game not found"
    players = game.get("user_players") or []
    if user_id not in players:
        return None, "Not authorized"
    if game.get("status") == "active":
        return None, "Finish the current game first"

    opponent_id = next((p for p in players if p != user_id), None)
    if opponent_id is None:
        return None, "Opponent not found"

    previous_color = (game.get("colors") or {}).get(user_id)
    preference = "black" if previous_color == "white" else "white"
    time_control = game.get("time_control") or {}
    surface = (game.get("surfaces") or {}).get(user_id) or SURFACE_APP

    return await create(
        db,
        user_id=user_id,
        opponent_id=opponent_id,
        time_control_key=time_control.get("key"),
        surface=surface,
        color_preference=preference,
    )


async def list_incoming(
    db: AsyncIOMotorDatabase, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    await expire_stale(db)
    rows = await list_for_user(db, user_id, incoming=True, status=PENDING)
    return {"items": await _hydrate(db, rows, user_id)}, None


async def list_outgoing(
    db: AsyncIOMotorDatabase, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    await expire_stale(db)
    rows = await list_for_user(db, user_id, incoming=False, status=PENDING)
    return {"items": await _hydrate(db, rows, user_id)}, None


def time_control_options() -> dict:
    """Selectable time controls, for the challenge form."""
    from backend.services.multiplayer_service import TIME_CONTROLS

    items = []
    for key, preset in TIME_CONTROLS.items():
        items.append(
            {
                "key": key,
                "label": preset["label"] if preset else "Unlimited",
                "initial_seconds": preset["initial_seconds"] if preset else None,
                "increment_seconds": preset["increment_seconds"] if preset else None,
            }
        )
    return {"items": items}
