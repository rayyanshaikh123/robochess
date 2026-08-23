from fastapi import APIRouter, Depends

from backend.api.schemas import (
    ApiResponse,
    ChallengeAcceptRequest,
    ChallengeCreateRequest,
    RematchRequest,
)
from backend.core.dependencies import get_current_user_id, rate_limit
from backend.db.client import get_db
from backend.realtime.events import (
    CHALLENGE_ACCEPTED,
    CHALLENGE_CANCELLED,
    CHALLENGE_RECEIVED,
    CHALLENGE_REJECTED,
    GAME_CREATED,
    notify_user,
)
from backend.services.challenge_service import (
    accept,
    cancel,
    create,
    create_rematch,
    list_incoming,
    list_outgoing,
    reject,
    time_control_options,
)
from backend.utils.helpers import error, ok

router = APIRouter()


@router.get("/time-controls", response_model=ApiResponse)
async def time_controls() -> ApiResponse:
    return ok("ok", time_control_options())


@router.get("/incoming", response_model=ApiResponse)
async def incoming(
    db=Depends(get_db), user_id: str = Depends(get_current_user_id)
) -> ApiResponse:
    data, err = await list_incoming(db, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.get("/outgoing", response_model=ApiResponse)
async def outgoing(
    db=Depends(get_db), user_id: str = Depends(get_current_user_id)
) -> ApiResponse:
    data, err = await list_outgoing(db, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.post("/create", response_model=ApiResponse)
async def create_challenge_endpoint(
    payload: ChallengeCreateRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await create(
        db,
        user_id,
        payload.opponent_id,
        time_control_key=payload.time_control,
        surface=payload.surface,
        color_preference=payload.color,
    )
    if err:
        return error(err)
    await notify_user(
        payload.opponent_id,
        CHALLENGE_RECEIVED,
        {"challenge_id": data.get("challenge_id"), "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/rematch", response_model=ApiResponse)
async def rematch(
    payload: RematchRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await create_rematch(db, user_id, payload.game_id)
    if err:
        return error(err)
    await notify_user(
        data["opponent"]["user_id"],
        CHALLENGE_RECEIVED,
        {"challenge_id": data.get("challenge_id"), "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/{challenge_id}/accept", response_model=ApiResponse)
async def accept_challenge(
    challenge_id: str,
    payload: ChallengeAcceptRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await accept(db, user_id, challenge_id, surface=payload.surface)
    if err:
        return error(err)
    game_id = data.get("game_id")
    # Both players need the new game id: the challenger to open the board, the
    # accepter because their own response only carries their view of it.
    for participant in (data.get("challenger_id"), data.get("challenged_id")):
        await notify_user(
            participant,
            GAME_CREATED,
            {"game_id": game_id, "challenge_id": challenge_id},
        )
    await notify_user(
        data.get("challenger_id"),
        CHALLENGE_ACCEPTED,
        {"challenge_id": challenge_id, "game_id": game_id, "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/{challenge_id}/reject", response_model=ApiResponse)
async def reject_challenge(
    challenge_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await reject(db, user_id, challenge_id)
    if err:
        return error(err)
    await notify_user(
        data.get("challenger_id"),
        CHALLENGE_REJECTED,
        {"challenge_id": challenge_id, "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/{challenge_id}/cancel", response_model=ApiResponse)
async def cancel_challenge(
    challenge_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await cancel(db, user_id, challenge_id)
    if err:
        return error(err)
    await notify_user(
        data.get("challenged_id"),
        CHALLENGE_CANCELLED,
        {"challenge_id": challenge_id, "user_id": user_id},
    )
    return ok("ok", data)
