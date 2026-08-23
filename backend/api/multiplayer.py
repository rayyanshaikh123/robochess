from fastapi import APIRouter, Depends

from backend.api.schemas import (
    ApiResponse,
    ChatMessageRequest,
    DrawResponseRequest,
    MultiplayerMoveRequest,
)
from backend.core.dependencies import get_current_user_id
from backend.db.client import get_db
from backend.realtime.events import (
    GAME_CHAT,
    GAME_DRAW_ACCEPTED,
    GAME_DRAW_OFFERED,
    GAME_DRAW_REJECTED,
    GAME_OVER,
    broadcast_move,
    notify_game,
    notify_user,
)
from backend.repositories.multiplayer_repo import get_game
from backend.services.multiplayer_service import (
    get_chat,
    get_game_for_user,
    list_games,
    offer_draw,
    post_chat,
    resign,
    respond_to_draw,
    submit_move,
)
from backend.utils.helpers import error, ok

router = APIRouter()


def _opponent_of(game: dict, user_id: str) -> str | None:
    return next((p for p in (game.get("user_players") or []) if p != user_id), None)


async def _announce_if_over(game_id: str, state: dict) -> None:
    if state.get("status") != "completed":
        return
    await notify_game(
        game_id,
        GAME_OVER,
        {
            "game_id": game_id,
            "result": state.get("result"),
            "winner_id": state.get("winner_id"),
            "end_reason": state.get("end_reason"),
        },
    )


@router.get("/games", response_model=ApiResponse)
async def games(
    scope: str = "active",
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await list_games(db, user_id, scope=scope)
    if err:
        return error(err)
    return ok("ok", data)


@router.get("/games/{game_id}", response_model=ApiResponse)
async def game_detail(
    game_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await get_game_for_user(db, game_id, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.post("/games/{game_id}/move", response_model=ApiResponse)
async def move(
    game_id: str,
    payload: MultiplayerMoveRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await submit_move(
        db, game_id, user_id, payload.uci, expected_version=payload.expected_version
    )
    if err:
        return error("Move rejected", {"detail": err})

    game = await get_game(db, game_id)
    await broadcast_move(
        game or {},
        {
            "game_id": game_id,
            "uci": payload.uci,
            "fen": data.get("current_fen"),
            "game_version": data.get("game_version"),
            "user_id": user_id,
        },
    )
    await _announce_if_over(game_id, data)
    return ok("Move accepted", data)


@router.post("/games/{game_id}/resign", response_model=ApiResponse)
async def resign_game(
    game_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await resign(db, game_id, user_id)
    if err:
        return error(err)
    await _announce_if_over(game_id, data)
    return ok("ok", data)


@router.post("/games/{game_id}/draw/offer", response_model=ApiResponse)
async def draw_offer(
    game_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await offer_draw(db, game_id, user_id)
    if err:
        return error(err)
    game = await get_game(db, game_id)
    await notify_user(
        _opponent_of(game or {}, user_id),
        GAME_DRAW_OFFERED,
        {"game_id": game_id, "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/games/{game_id}/draw/respond", response_model=ApiResponse)
async def draw_respond(
    game_id: str,
    payload: DrawResponseRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await respond_to_draw(db, game_id, user_id, accept=payload.accept)
    if err:
        return error(err)
    event = GAME_DRAW_ACCEPTED if payload.accept else GAME_DRAW_REJECTED
    await notify_game(game_id, event, {"game_id": game_id, "user_id": user_id})
    await _announce_if_over(game_id, data)
    return ok("ok", data)


@router.get("/games/{game_id}/chat", response_model=ApiResponse)
async def chat_history(
    game_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await get_chat(db, game_id, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.post("/games/{game_id}/chat", response_model=ApiResponse)
async def send_chat(
    game_id: str,
    payload: ChatMessageRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await post_chat(db, game_id, user_id, payload.text)
    if err:
        return error(err)
    await notify_game(game_id, GAME_CHAT, data)
    return ok("ok", data)
