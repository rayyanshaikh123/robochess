from datetime import datetime, timedelta, timezone
import secrets
from typing import Optional
from uuid import uuid4

from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.core.config import load_settings
from backend.core.security import create_device_token, hash_password, verify_password
from backend.repositories.device_repo import (
    create_device,
    get_by_device_id,
    get_by_hardware_id,
    get_by_ble_pair_token,
    get_by_pairing_code,
    link_user,
    list_by_user,
    restore_pairing_code,
    unlink_by_user,
    update_status,
    update_ble_pair_token,
)
from backend.realtime.manager import manager as ws_manager

_LOCAL_HARDWARE_ID = "local"


def _generate_pairing_code(length: int = 6) -> str:
    digits = "0123456789"
    return "".join(secrets.choice(digits) for _ in range(length))


async def _ensure_local_device(db: AsyncIOMotorDatabase) -> Optional[dict]:
    settings = load_settings()
    pairing_code = settings.local_pairing_code.strip()
    if not pairing_code:
        return None

    device = await get_by_hardware_id(db, _LOCAL_HARDWARE_ID)
    if device:
        return device

    device_id = str(uuid4())
    device_secret = secrets.token_urlsafe(32)
    pairing_expires_at = datetime.now(timezone.utc) + timedelta(days=3650)
    device_secret_hash = hash_password(device_secret)

    await create_device(
        db,
        device_id=device_id,
        device_secret_hash=device_secret_hash,
        pairing_code=pairing_code,
        pairing_expires_at=pairing_expires_at,
        hardware_id=_LOCAL_HARDWARE_ID,
    )

    return await get_by_device_id(db, device_id)


async def register_device(
    db: AsyncIOMotorDatabase, hardware_id: Optional[str]
) -> tuple[Optional[dict], Optional[str]]:
    if hardware_id:
        existing = await get_by_hardware_id(db, hardware_id)
        if existing:
            return None, "Device already registered"

    settings = load_settings()
    device_id = str(uuid4())
    device_secret = secrets.token_urlsafe(32)
    pairing_code = _generate_pairing_code()
    pairing_expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.pairing_code_minutes
    )
    device_secret_hash = hash_password(device_secret)

    await create_device(
        db,
        device_id=device_id,
        device_secret_hash=device_secret_hash,
        pairing_code=pairing_code,
        pairing_expires_at=pairing_expires_at,
        hardware_id=hardware_id,
    )

    token = create_device_token(device_id, settings)
    return {
        "device_id": device_id,
        "device_secret": device_secret,
        "device_token": token,
        "pairing_code": pairing_code,
        "pairing_expires_at": pairing_expires_at,
    }, None


async def connect_device(
    db: AsyncIOMotorDatabase, device_id: str, device_secret: str
) -> tuple[Optional[dict], Optional[str]]:
    device = await get_by_device_id(db, device_id)
    if not device:
        return None, "Device not found"

    if not verify_password(device_secret, device.get("device_secret_hash", "")):
        return None, "Invalid device secret"

    settings = load_settings()
    await update_status(db, device_id, "connected")
    await ws_manager.send_to_game(
        f"device:{device_id}",
        {
            "type": "device.status",
            "data": {
                "device_id": device_id,
                "status": "connected",
                "last_seen": datetime.now(timezone.utc),
            },
        },
    )
    token = create_device_token(device_id, settings)
    return {"device_id": device_id, "device_token": token, "status": "connected"}, None


async def create_ble_pair_token(
    db: AsyncIOMotorDatabase, device_id: str
) -> tuple[Optional[dict], Optional[str]]:
    device = await get_by_device_id(db, device_id)
    if not device:
        return None, "Device not found"

    settings = load_settings()
    token = secrets.token_hex(8)
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ble_pair_token_minutes
    )
    await update_ble_pair_token(db, device_id, token, expires_at)
    return {
        "device_id": device_id,
        "ble_pair_token": token,
        "ble_pair_expires_at": expires_at,
    }, None


async def disconnect_device(db: AsyncIOMotorDatabase, device_id: str) -> None:
    await update_status(db, device_id, "disconnected")
    await ws_manager.send_to_game(
        f"device:{device_id}",
        {
            "type": "device.status",
            "data": {
                "device_id": device_id,
                "status": "disconnected",
                "last_seen": datetime.now(timezone.utc),
            },
        },
    )


async def heartbeat_device(db: AsyncIOMotorDatabase, device_id: str) -> None:
    await update_status(db, device_id, "connected")
    await ws_manager.send_to_game(
        f"device:{device_id}",
        {
            "type": "device.status",
            "data": {
                "device_id": device_id,
                "status": "connected",
                "last_seen": datetime.now(timezone.utc),
            },
        },
    )


async def link_device(
    db: AsyncIOMotorDatabase, user_id: str, pairing_code: str
) -> tuple[Optional[dict], Optional[str]]:
    settings = load_settings()
    if pairing_code == settings.local_pairing_code:
        device = await _ensure_local_device(db)
        if not device:
            return None, "Local device unavailable"
        current_user_id = device.get("user_id")
        if current_user_id and str(current_user_id) != user_id:
            return None, "Device already linked"
        await link_user(db, device["device_id"], user_id)
        await update_status(db, device["device_id"], "connected")
        return {"device_id": device["device_id"], "local": True}, None

    device = await get_by_pairing_code(db, pairing_code)
    if not device:
        return None, "Invalid pairing code"

    expires_at = device.get("pairing_expires_at")
    if not expires_at or expires_at <= datetime.now(timezone.utc):
        return None, "Pairing code expired"

    current_user_id = device.get("user_id")
    if current_user_id and str(current_user_id) != user_id:
        return None, "Device already linked"

    await link_user(db, device["device_id"], user_id)
    return {"device_id": device["device_id"]}, None


async def link_device_ble(
    db: AsyncIOMotorDatabase, user_id: str, token: str
) -> tuple[Optional[dict], Optional[str]]:
    device = await get_by_ble_pair_token(db, token)
    if not device:
        return None, "Invalid BLE token"

    expires_at = device.get("ble_pair_expires_at")
    if not expires_at or expires_at <= datetime.now(timezone.utc):
        return None, "BLE token expired"

    current_user_id = device.get("user_id")
    if current_user_id and str(current_user_id) != user_id:
        return None, "Device already linked"

    await link_user(db, device["device_id"], user_id)
    return {"device_id": device["device_id"]}, None


async def get_device_status(
    db: AsyncIOMotorDatabase, device_id: str, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    device = await get_by_device_id(db, device_id)
    if not device:
        return None, "Device not found"

    stored_user_id = device.get("user_id")
    if stored_user_id and str(stored_user_id) != user_id:
        return None, "Forbidden"

    return {
        "device_id": device_id,
        "status": device.get("status", "unknown"),
        "last_seen": device.get("last_seen"),
    }, None


async def list_devices(db: AsyncIOMotorDatabase, user_id: str) -> list[dict]:
    devices = await list_by_user(db, user_id)
    return [
        {
            "device_id": device.get("device_id"),
            "status": device.get("status", "unknown"),
            "last_seen": device.get("last_seen"),
        }
        for device in devices
    ]


async def unlink_device(
    db: AsyncIOMotorDatabase, user_id: str, device_id: str
) -> tuple[bool, Optional[str]]:
    success = await unlink_by_user(db, user_id, device_id)
    if not success:
        return False, "Device not found"
    device = await get_by_device_id(db, device_id)
    if device and device.get("hardware_id") == _LOCAL_HARDWARE_ID:
        settings = load_settings()
        await restore_pairing_code(
            db,
            device_id,
            settings.local_pairing_code,
            datetime.now(timezone.utc) + timedelta(days=3650),
        )
    await ws_manager.send_to_game(
        f"device:{device_id}",
        {
            "type": "device.status",
            "data": {
                "device_id": device_id,
                "status": "disconnected",
                "last_seen": datetime.now(timezone.utc),
            },
        },
    )
    return True, None
