from typing import Optional

from jose import JWTError
from motor.motor_asyncio import AsyncIOMotorDatabase
from pymongo.errors import PyMongoError, ServerSelectionTimeoutError

from backend.core.config import load_settings
from backend.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    hash_token,
    verify_password,
)
from backend.repositories.token_repo import (
    find_valid_refresh_token,
    insert_refresh_token,
    revoke_refresh_token,
)
from backend.repositories.user_repo import create_user, get_by_email


def _db_error_message(exc: Exception, fallback: str) -> str:
    if isinstance(exc, ServerSelectionTimeoutError):
        return "Database timeout. Try again."
    return fallback


async def register_user(
    db: AsyncIOMotorDatabase,
    email: str,
    password: str,
    display_name: Optional[str],
    device_id: Optional[str],
) -> tuple[Optional[dict], Optional[str]]:
    try:
        clean_email = email.strip().lower()
        existing = await get_by_email(db, clean_email)
        if existing:
            return None, "Email already registered"

        settings = load_settings()
        name = display_name.strip() if display_name else clean_email.split("@")[0]
        password_hash = hash_password(password)
        user = await create_user(db, clean_email, password_hash, name, is_guest=False)
        user_id = str(user["_id"])

        access_token = create_access_token(user_id, settings)
        refresh_token, expires_at = create_refresh_token(user_id, settings)
        await insert_refresh_token(db, user_id, device_id, hash_token(refresh_token), expires_at)

        return {"user_id": user_id, "access_token": access_token, "refresh_token": refresh_token}, None
    except PyMongoError as exc:
        return None, _db_error_message(exc, "Registration unavailable. Try again.")


async def login_user(
    db: AsyncIOMotorDatabase,
    email: str,
    password: str,
    device_id: Optional[str],
) -> tuple[Optional[dict], Optional[str]]:
    try:
        clean_email = email.strip().lower()
        user = await get_by_email(db, clean_email)
        if not user:
            return None, "Invalid credentials"

        if not verify_password(password, user.get("password_hash", "")):
            return None, "Invalid credentials"

        settings = load_settings()
        user_id = str(user["_id"])
        access_token = create_access_token(user_id, settings)
        refresh_token, expires_at = create_refresh_token(user_id, settings)
        await insert_refresh_token(db, user_id, device_id, hash_token(refresh_token), expires_at)

        return {"user_id": user_id, "access_token": access_token, "refresh_token": refresh_token}, None
    except PyMongoError as exc:
        return None, _db_error_message(exc, "Login unavailable. Try again.")


async def refresh_session(
    db: AsyncIOMotorDatabase, refresh_token: str
) -> tuple[Optional[dict], Optional[str]]:
    try:
        settings = load_settings()
        try:
            payload = decode_token(refresh_token, settings)
        except JWTError:
            return None, "Invalid refresh token"

        if payload.get("type") != "refresh":
            return None, "Invalid refresh token"

        user_id = payload.get("sub")
        if not user_id:
            return None, "Invalid refresh token"

        token_hash = hash_token(refresh_token)
        stored = await find_valid_refresh_token(db, token_hash)
        if not stored:
            return None, "Refresh token revoked"

        await revoke_refresh_token(db, token_hash)

        access_token = create_access_token(user_id, settings)
        new_refresh_token, expires_at = create_refresh_token(user_id, settings)
        await insert_refresh_token(db, user_id, stored.get("device_id"), hash_token(new_refresh_token), expires_at)

        return {"user_id": user_id, "access_token": access_token, "refresh_token": new_refresh_token}, None
    except PyMongoError as exc:
        return None, _db_error_message(exc, "Session refresh unavailable. Try again.")


async def logout_user(db: AsyncIOMotorDatabase, refresh_token: str) -> None:
    token_hash = hash_token(refresh_token)
    await revoke_refresh_token(db, token_hash)
