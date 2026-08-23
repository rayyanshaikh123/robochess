from fastapi import APIRouter, Depends

from backend.api.schemas import ApiResponse, FriendRemoveRequest, FriendRequestCreate
from backend.core.dependencies import get_current_user_id, rate_limit
from backend.db.client import get_db
from backend.realtime.events import (
    FRIEND_REMOVED,
    FRIEND_REQUEST_ACCEPTED,
    FRIEND_REQUEST_CANCELLED,
    FRIEND_REQUEST_RECEIVED,
    FRIEND_REQUEST_REJECTED,
    notify_user,
)
from backend.services.friendship_service import (
    cancel_request,
    list_friends,
    list_incoming_requests,
    list_outgoing_requests,
    remove_friend,
    respond_to_request,
    send_request,
)
from backend.services.user_search_service import search
from backend.utils.helpers import error, ok

router = APIRouter()


@router.get("/list", response_model=ApiResponse)
async def friends(
    db=Depends(get_db), user_id: str = Depends(get_current_user_id)
) -> ApiResponse:
    data, err = await list_friends(db, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.get("/requests/incoming", response_model=ApiResponse)
async def incoming(
    db=Depends(get_db), user_id: str = Depends(get_current_user_id)
) -> ApiResponse:
    data, err = await list_incoming_requests(db, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.get("/requests/outgoing", response_model=ApiResponse)
async def outgoing(
    db=Depends(get_db), user_id: str = Depends(get_current_user_id)
) -> ApiResponse:
    data, err = await list_outgoing_requests(db, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.get("/search", response_model=ApiResponse)
async def search_users_endpoint(
    q: str = "",
    limit: int = 20,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await search(db, user_id, q, limit=limit)
    if err:
        return error(err)
    return ok("ok", data)


@router.post("/request", response_model=ApiResponse)
async def create_request(
    payload: FriendRequestCreate,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await send_request(db, user_id, payload.user_id)
    if err:
        return error(err)
    # A mirrored request turns into an immediate friendship, so tell the other
    # side which of the two actually happened.
    event = FRIEND_REQUEST_ACCEPTED if data.get("auto_accepted") else FRIEND_REQUEST_RECEIVED
    await notify_user(payload.user_id, event, {"friendship_id": data.get("friendship_id"),
                                               "user_id": user_id})
    return ok("ok", data)


@router.post("/requests/{friendship_id}/accept", response_model=ApiResponse)
async def accept_request(
    friendship_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await respond_to_request(db, user_id, friendship_id, accept=True)
    if err:
        return error(err)
    await notify_user(
        data["user"]["user_id"],
        FRIEND_REQUEST_ACCEPTED,
        {"friendship_id": friendship_id, "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/requests/{friendship_id}/reject", response_model=ApiResponse)
async def reject_request(
    friendship_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await respond_to_request(db, user_id, friendship_id, accept=False)
    if err:
        return error(err)
    await notify_user(
        data["user"]["user_id"],
        FRIEND_REQUEST_REJECTED,
        {"friendship_id": friendship_id, "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/requests/{friendship_id}/cancel", response_model=ApiResponse)
async def cancel_sent_request(
    friendship_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await cancel_request(db, user_id, friendship_id)
    if err:
        return error(err)
    await notify_user(
        data.get("user_id"),
        FRIEND_REQUEST_CANCELLED,
        {"friendship_id": friendship_id, "user_id": user_id},
    )
    return ok("ok", data)


@router.post("/remove", response_model=ApiResponse)
async def unfriend(
    payload: FriendRemoveRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await remove_friend(db, user_id, payload.user_id)
    if err:
        return error(err)
    await notify_user(payload.user_id, FRIEND_REMOVED, {"user_id": user_id})
    return ok("ok", data)
