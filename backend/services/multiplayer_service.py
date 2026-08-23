"""Authoritative multiplayer game logic.

The client is never trusted: turn order, legality, results and clocks are all
decided here. Move legality and version handling reuse
``game_service.validate_and_record_move`` rather than duplicating chess rules.
"""

from datetime import datetime, timedelta, timezone
import random
from typing import Optional

import chess
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.repositories.multiplayer_repo import (
    add_chat,
    create_multiplayer_game,
    finish_game,
    get_game,
    list_chat,
    list_for_user,
    set_draw_offer,
    set_turn_started,
    update_clocks,
)
from backend.repositories.user_repo import get_many_by_ids
from backend.services.game_service import validate_and_record_move

WHITE = "white"
BLACK = "black"
SURFACE_APP = "app"

RESULT_WHITE = "1-0"
RESULT_BLACK = "0-1"
RESULT_DRAW = "1/2-1/2"

ACTIVE_STATUSES = ["active"]
COMPLETED_STATUSES = ["completed"]

#: Selectable time controls. ``None`` means an untimed game.
TIME_CONTROLS: dict[str, Optional[dict]] = {
    "unlimited": None,
    "bullet_1_0": {"label": "Bullet 1+0", "initial_seconds": 60, "increment_seconds": 0},
    "blitz_3_2": {"label": "Blitz 3+2", "initial_seconds": 180, "increment_seconds": 2},
    "blitz_5_0": {"label": "Blitz 5+0", "initial_seconds": 300, "increment_seconds": 0},
    "rapid_10_0": {"label": "Rapid 10+0", "initial_seconds": 600, "increment_seconds": 0},
    "rapid_15_10": {"label": "Rapid 15+10", "initial_seconds": 900, "increment_seconds": 10},
}


def resolve_time_control(key: Optional[str]) -> tuple[Optional[dict], Optional[str]]:
    """Look up a preset by key. Unknown keys are rejected rather than defaulted."""
    if key is None or key == "":
        return None, None
    if key not in TIME_CONTROLS:
        return None, f"Unknown time control '{key}'"
    preset = TIME_CONTROLS[key]
    if preset is None:
        return None, None
    return {**preset, "key": key}, None


def derive_play_mode(surface_a: str, surface_b: str) -> str:
    a_is_board = surface_a != SURFACE_APP
    b_is_board = surface_b != SURFACE_APP
    if a_is_board and b_is_board:
        return "board_vs_board"
    if a_is_board or b_is_board:
        return "app_vs_board"
    return "app_vs_app"


def _iso(value) -> Optional[str]:
    return value.isoformat() if hasattr(value, "isoformat") else None


def _as_aware(value) -> Optional[datetime]:
    """Mongo can hand back naive datetimes; treat those as UTC."""
    if not isinstance(value, datetime):
        return None
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def side_to_move(fen: str) -> Optional[str]:
    try:
        return WHITE if chess.Board(fen).turn == chess.WHITE else BLACK
    except Exception:
        return None


def _user_for_color(game: dict, color: str) -> Optional[str]:
    for user_id, assigned in (game.get("colors") or {}).items():
        if assigned == color:
            return user_id
    return None


def assign_colors(
    challenger_id: str, challenged_id: str, preference: str
) -> dict[str, str]:
    if preference == WHITE:
        challenger_color = WHITE
    elif preference == BLACK:
        challenger_color = BLACK
    else:
        challenger_color = random.choice([WHITE, BLACK])
    other = BLACK if challenger_color == WHITE else WHITE
    return {challenger_id: challenger_color, challenged_id: other}


def _initial_clocks(
    time_control: Optional[dict], user_ids: list[str]
) -> Optional[dict]:
    if not time_control:
        return None
    initial_ms = int(time_control["initial_seconds"]) * 1000
    return {user_id: {"remaining_ms": initial_ms} for user_id in user_ids}


def serialize_game(game: dict, user_id: str, profiles: Optional[dict] = None) -> dict:
    """Game as seen by one participant."""
    colors = game.get("colors") or {}
    user_players = game.get("user_players") or []
    opponent_id = next((p for p in user_players if p != user_id), None)
    fen = game.get("current_fen") or ""
    turn_color = side_to_move(fen)
    your_color = colors.get(user_id)
    result = game.get("result")
    winner_id = game.get("winner_id")

    if result is None:
        your_result = None
    elif result == RESULT_DRAW:
        your_result = "draw"
    elif winner_id == user_id:
        your_result = "won"
    else:
        your_result = "lost"

    opponent_profile = (profiles or {}).get(opponent_id) if opponent_id else None
    return {
        "game_id": str(game["_id"]),
        "current_fen": fen,
        "status": game.get("status"),
        "game_version": game.get("game_version", 0),
        "last_move": game.get("last_move"),
        "your_color": your_color,
        "opponent_color": colors.get(opponent_id) if opponent_id else None,
        "turn": turn_color,
        "your_turn": bool(your_color and turn_color == your_color and game.get("status") == "active"),
        "opponent": {
            "user_id": opponent_id or "",
            "display_name": (opponent_profile or {}).get("display_name") or "Opponent",
            "rating": (opponent_profile or {}).get("rating"),
        },
        "play_mode": game.get("play_mode"),
        "your_surface": (game.get("surfaces") or {}).get(user_id),
        "time_control": game.get("time_control"),
        "clocks": game.get("clocks"),
        "turn_started_at": _iso(game.get("turn_started_at")),
        "result": result,
        "your_result": your_result,
        "winner_id": winner_id,
        "end_reason": game.get("end_reason"),
        "draw_offer_by": game.get("draw_offer_by"),
        "rematch_of": game.get("rematch_of"),
        "created_at": _iso(game.get("created_at")),
        "updated_at": _iso(game.get("updated_at")),
    }


async def _load_participant_game(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    """Fetch a game only if the caller is actually playing in it."""
    game = await get_game(db, game_id)
    if not game:
        return None, "Game not found"
    if user_id not in (game.get("user_players") or []):
        return None, "Not authorized"
    return game, None


async def create_game_for_players(
    db: AsyncIOMotorDatabase,
    challenger_id: str,
    challenged_id: str,
    time_control: Optional[dict],
    challenger_surface: str,
    challenged_surface: str,
    color_preference: str,
    rematch_of: Optional[str] = None,
) -> dict:
    colors = assign_colors(challenger_id, challenged_id, color_preference)
    user_players = [challenger_id, challenged_id]
    surfaces = {
        challenger_id: challenger_surface,
        challenged_id: challenged_surface,
    }
    game = await create_multiplayer_game(
        db,
        user_players=user_players,
        colors=colors,
        surfaces=surfaces,
        play_mode=derive_play_mode(challenger_surface, challenged_surface),
        current_fen=chess.Board().fen(),
        time_control=time_control,
        clocks=_initial_clocks(time_control, user_players),
        rematch_of=rematch_of,
    )
    # White's clock starts the moment the game exists, so the first move is
    # billed like every other one.
    if time_control:
        await set_turn_started(db, str(game["_id"]), datetime.now(timezone.utc))
        game["turn_started_at"] = datetime.now(timezone.utc)
    return game


async def get_game_for_user(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    game, err = await _load_participant_game(db, game_id, user_id)
    if err:
        return None, err
    opponent = next(
        (p for p in (game.get("user_players") or []) if p != user_id), None
    )
    profiles = await get_many_by_ids(db, [opponent]) if opponent else {}
    return serialize_game(game, user_id, profiles), None


async def list_games(
    db: AsyncIOMotorDatabase, user_id: str, scope: str = "active"
) -> tuple[Optional[dict], Optional[str]]:
    if scope == "active":
        statuses = ACTIVE_STATUSES
    elif scope == "completed":
        statuses = COMPLETED_STATUSES
    elif scope == "all":
        statuses = None
    else:
        return None, "Unknown scope"

    games = await list_for_user(db, user_id, statuses)
    opponents = [
        p
        for game in games
        for p in (game.get("user_players") or [])
        if p != user_id
    ]
    profiles = await get_many_by_ids(db, opponents)
    return {"items": [serialize_game(g, user_id, profiles) for g in games]}, None


def _apply_clock(
    game: dict, mover_id: str, now: datetime
) -> tuple[Optional[dict], bool]:
    """Deduct the mover's elapsed time and add their increment.

    Returns the updated clock map and whether the mover ran out of time.
    """
    time_control = game.get("time_control")
    clocks = game.get("clocks")
    if not time_control or not clocks:
        return None, False

    started = _as_aware(game.get("turn_started_at")) or _as_aware(game.get("updated_at"))
    elapsed_ms = 0
    if started is not None:
        elapsed_ms = max(0, int((now - started).total_seconds() * 1000))

    updated = {uid: dict(entry) for uid, entry in clocks.items()}
    mover = updated.setdefault(mover_id, {"remaining_ms": 0})
    remaining = int(mover.get("remaining_ms", 0)) - elapsed_ms
    if remaining <= 0:
        mover["remaining_ms"] = 0
        return updated, True
    mover["remaining_ms"] = remaining + int(time_control.get("increment_seconds", 0)) * 1000
    return updated, False


def _outcome_after_move(board: chess.Board, mover_id: str, opponent_id: Optional[str]):
    """Result triple for a finished position, or ``None`` if play continues."""
    if board.is_checkmate():
        winner_color = BLACK if board.turn == chess.WHITE else WHITE
        result = RESULT_WHITE if winner_color == WHITE else RESULT_BLACK
        return result, mover_id, "checkmate"
    if board.is_stalemate():
        return RESULT_DRAW, None, "stalemate"
    if board.is_insufficient_material():
        return RESULT_DRAW, None, "insufficient_material"
    if board.is_seventyfive_moves():
        return RESULT_DRAW, None, "seventyfive_moves"
    if board.is_fivefold_repetition():
        return RESULT_DRAW, None, "fivefold_repetition"
    return None


async def submit_move(
    db: AsyncIOMotorDatabase,
    game_id: str,
    user_id: str,
    uci: str,
    expected_version: Optional[int] = None,
) -> tuple[Optional[dict], Optional[str]]:
    game, err = await _load_participant_game(db, game_id, user_id)
    if err:
        return None, err
    if game.get("status") != "active":
        return None, "Game is already finished"

    colors = game.get("colors") or {}
    your_color = colors.get(user_id)
    turn_color = side_to_move(game.get("current_fen") or "")
    if your_color is None or turn_color is None:
        return None, "Game state is invalid"
    if your_color != turn_color:
        return None, "It is not your turn"

    opponent_id = next(
        (p for p in (game.get("user_players") or []) if p != user_id), None
    )
    now = datetime.now(timezone.utc)
    clocks, flagged = _apply_clock(game, user_id, now)
    if flagged:
        # The mover's own clock expired before the move landed.
        result = RESULT_BLACK if your_color == WHITE else RESULT_WHITE
        await update_clocks(db, game_id, clocks or {})
        await finish_game(db, game_id, result, opponent_id, "timeout")
        finished = await get_game(db, game_id)
        profiles = await get_many_by_ids(db, [opponent_id]) if opponent_id else {}
        return serialize_game(finished or game, user_id, profiles), None

    state, move_error = await validate_and_record_move(
        db, game_id, uci, expected_version=expected_version
    )
    if move_error:
        return None, move_error

    if clocks is not None:
        await update_clocks(db, game_id, clocks)
    await set_turn_started(db, game_id, now)

    # A move always answers any outstanding draw offer.
    if game.get("draw_offer_by"):
        await set_draw_offer(db, game_id, None)

    outcome = None
    try:
        outcome = _outcome_after_move(
            chess.Board(state.get("current_fen") or ""), user_id, opponent_id
        )
    except Exception:
        outcome = None
    if outcome:
        result, winner_id, reason = outcome
        await finish_game(db, game_id, result, winner_id, reason)

    fresh = await get_game(db, game_id)
    profiles = await get_many_by_ids(db, [opponent_id]) if opponent_id else {}
    return serialize_game(fresh or game, user_id, profiles), None


async def resign(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    game, err = await _load_participant_game(db, game_id, user_id)
    if err:
        return None, err
    if game.get("status") != "active":
        return None, "Game is already finished"

    colors = game.get("colors") or {}
    opponent_id = next(
        (p for p in (game.get("user_players") or []) if p != user_id), None
    )
    result = RESULT_BLACK if colors.get(user_id) == WHITE else RESULT_WHITE
    if not await finish_game(db, game_id, result, opponent_id, "resignation"):
        return None, "Game is already finished"

    fresh = await get_game(db, game_id)
    profiles = await get_many_by_ids(db, [opponent_id]) if opponent_id else {}
    return serialize_game(fresh or game, user_id, profiles), None


async def offer_draw(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    game, err = await _load_participant_game(db, game_id, user_id)
    if err:
        return None, err
    if game.get("status") != "active":
        return None, "Game is already finished"
    if game.get("draw_offer_by") == user_id:
        return None, "You already offered a draw"
    if not await set_draw_offer(db, game_id, user_id):
        return None, "Could not offer a draw"
    fresh = await get_game(db, game_id)
    return serialize_game(fresh or game, user_id), None


async def respond_to_draw(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str, accept: bool
) -> tuple[Optional[dict], Optional[str]]:
    game, err = await _load_participant_game(db, game_id, user_id)
    if err:
        return None, err
    if game.get("status") != "active":
        return None, "Game is already finished"

    offered_by = game.get("draw_offer_by")
    if not offered_by:
        return None, "No draw has been offered"
    if offered_by == user_id:
        return None, "You cannot answer your own draw offer"

    if accept:
        if not await finish_game(db, game_id, RESULT_DRAW, None, "draw_agreed"):
            return None, "Game is already finished"
    else:
        await set_draw_offer(db, game_id, None)

    fresh = await get_game(db, game_id)
    opponent_id = next(
        (p for p in (game.get("user_players") or []) if p != user_id), None
    )
    profiles = await get_many_by_ids(db, [opponent_id]) if opponent_id else {}
    return serialize_game(fresh or game, user_id, profiles), None


async def post_chat(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str, text: str
) -> tuple[Optional[dict], Optional[str]]:
    message = (text or "").strip()
    if not message:
        return None, "Message cannot be empty"
    if len(message) > 500:
        return None, "Message is too long"
    _, err = await _load_participant_game(db, game_id, user_id)
    if err:
        return None, err
    row = await add_chat(db, game_id, user_id, message)
    return {
        "message_id": str(row["_id"]),
        "game_id": game_id,
        "user_id": user_id,
        "text": message,
        "created_at": _iso(row.get("created_at")),
    }, None


async def get_chat(
    db: AsyncIOMotorDatabase, game_id: str, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    _, err = await _load_participant_game(db, game_id, user_id)
    if err:
        return None, err
    rows = await list_chat(db, game_id)
    return {
        "items": [
            {
                "message_id": str(row["_id"]),
                "user_id": row.get("user_id"),
                "text": row.get("text"),
                "created_at": _iso(row.get("created_at")),
            }
            for row in rows
        ]
    }, None
