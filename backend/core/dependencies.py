from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError

from backend.core.config import load_settings
from backend.core.security import decode_token
from backend.utils.rate_limit import rate_limiter

_bearer = HTTPBearer()


def _get_subject(credentials: HTTPAuthorizationCredentials, expected_type: str) -> str:
    settings = load_settings()
    try:
        payload = decode_token(credentials.credentials, settings)
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    if payload.get("type") != expected_type:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    subject = payload.get("sub")
    if not subject:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    return subject


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> str:
    return _get_subject(credentials, "access")


async def get_current_device_id(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> str:
    return _get_subject(credentials, "device")


async def rate_limit(request: Request) -> None:
    settings = load_settings()
    client_host = request.client.host if request.client else "unknown"
    key = f"{client_host}:{request.url.path}"
    allowed = rate_limiter.allow(
        key, settings.rate_limit_requests, settings.rate_limit_window_seconds
    )
    if not allowed:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many requests")
