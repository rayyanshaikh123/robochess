from datetime import datetime, timedelta, timezone
import hashlib
from typing import Any

from jose import jwt
from passlib.context import CryptContext

from backend.core.config import Settings

_password_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return _password_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return _password_context.verify(password, password_hash)


def _create_token(subject: str, token_type: str, exp_delta: timedelta, settings: Settings) -> str:
    now = datetime.now(timezone.utc)
    exp = now + exp_delta
    payload: dict[str, Any] = {"sub": subject, "type": token_type, "exp": exp}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_access_token(subject: str, settings: Settings) -> str:
    return _create_token(subject, "access", timedelta(minutes=settings.access_token_minutes), settings)


def create_refresh_token(subject: str, settings: Settings) -> tuple[str, datetime]:
    exp = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_days)
    token = _create_token(subject, "refresh", timedelta(days=settings.refresh_token_days), settings)
    return token, exp


def create_device_token(device_id: str, settings: Settings) -> str:
    return _create_token(
        device_id, "device", timedelta(minutes=settings.device_token_minutes), settings
    )


def decode_token(token: str, settings: Settings) -> dict[str, Any]:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
