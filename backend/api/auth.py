from fastapi import APIRouter, Depends

from backend.api.schemas import ApiResponse, LoginRequest, LogoutRequest, RefreshRequest, RegisterRequest
from backend.core.dependencies import get_current_user_id, rate_limit
from backend.db.client import get_db
from backend.repositories.user_repo import get_by_id
from backend.services.auth_service import login_user, logout_user, refresh_session, register_user
from backend.services.user_stats_service import get_user_stats
from backend.utils.helpers import error, ok

router = APIRouter()


@router.post("/register", response_model=ApiResponse)
async def register(
    payload: RegisterRequest,
    db=Depends(get_db),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await register_user(
        db,
        email=payload.email,
        password=payload.password,
        display_name=payload.display_name,
        device_id=payload.device_id,
    )
    if err:
        return error(err)
    return ok("Registered", data)


@router.post("/login", response_model=ApiResponse)
async def login(
    payload: LoginRequest,
    db=Depends(get_db),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await login_user(db, payload.email, payload.password, payload.device_id)
    if err:
        return error(err)
    return ok("Logged in", data)


@router.post("/refresh", response_model=ApiResponse)
async def refresh(
    payload: RefreshRequest,
    db=Depends(get_db),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await refresh_session(db, payload.refresh_token)
    if err:
        return error(err)
    return ok("Token refreshed", data)


@router.post("/logout", response_model=ApiResponse)
async def logout(payload: LogoutRequest, db=Depends(get_db)) -> ApiResponse:
    await logout_user(db, payload.refresh_token)
    return ok("Logged out")


@router.get("/me", response_model=ApiResponse)
async def me(
    user_id: str = Depends(get_current_user_id),
    db=Depends(get_db),
) -> ApiResponse:
    user = await get_by_id(db, user_id)
    if not user:
        return error("User not found")
    created_at = user.get("created_at")
    data = {
        "user_id": str(user.get("_id")),
        "email": user.get("email"),
        "display_name": user.get("display_name"),
        "created_at": created_at.isoformat() if created_at else None,
    }
    return ok("ok", data)


@router.get("/stats", response_model=ApiResponse)
async def stats(
    user_id: str = Depends(get_current_user_id),
    db=Depends(get_db),
) -> ApiResponse:
    data = await get_user_stats(db, user_id)
    return ok("ok", data)
