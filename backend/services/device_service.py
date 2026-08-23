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
    update_device_secret,
    consume_onboarding_token,
    save_onboarding_token,
    update_device_metadata,
)
from backend.realtime.manager import manager as ws_manager

_LOCAL_HARDWARE_ID = "local"
DEVICE_STATES = {
    "unpaired", "ble_connected", "provisioning_wifi", "wifi_connecting",
    "wifi_connected", "server_connecting", "online", "offline", "error",
}


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


async def create_onboarding_token(
    db: AsyncIOMotorDatabase, user_id: str, device_id: str
) -> tuple[Optional[dict], Optional[str]]:
    device = await get_by_device_id(db, device_id)
    device_secret = None

    if device is None:
        settings = load_settings()
        device_secret = secrets.token_urlsafe(32)
        pairing_expires_at = datetime.now(timezone.utc) + timedelta(
            minutes=settings.pairing_code_minutes
        )
        try:
            device = await create_device(
                db,
                device_id=device_id,
                device_secret_hash=hash_password(device_secret),
                pairing_code="",
                pairing_expires_at=pairing_expires_at,
                hardware_id=device_id,
            )
        except Exception:
            device = await get_by_device_id(db, device_id)
            if device is None:
                raise
            device_secret = None
    current_user_id = device.get("user_id") if device else None
    if current_user_id and str(current_user_id) != user_id:
        return None, "Device already linked"

    # Rotate credentials for every unlinked device so a failed BLE transfer
    # can be retried without exposing an existing secret.
    if device_secret is None and device and not current_user_id:
        device_secret = secrets.token_urlsafe(32)
        await update_device_secret(db, device_id, hash_password(device_secret))

    settings = load_settings()
    token = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ble_pair_token_minutes
    )
    await save_onboarding_token(
        db, device_id, hash_password(token), expires_at, user_id
    )
    data = {
        "device_id": device_id,
        "onboarding_token": token,
        "expires_at": expires_at,
    }
    if device_secret is not None:
        data["device_secret"] = device_secret
    return data, None


async def claim_device(
    db: AsyncIOMotorDatabase, device_id: str, onboarding_token: str
) -> tuple[Optional[dict], Optional[str]]:
    device = await get_by_device_id(db, device_id)
    if not device:
        return None, "Device not found"
    token_hash = device.get("onboarding_token_hash")
    expires_at = device.get("onboarding_token_expires_at")
    if not token_hash or not expires_at or expires_at <= datetime.now(timezone.utc):
        return None, "Onboarding token expired"
    if not verify_password(onboarding_token, token_hash):
        return None, "Invalid onboarding token"
    onboarding_user_id = device.get("onboarding_user_id")
    if not onboarding_user_id:
        return None, "Onboarding token is not bound to a user"
    current_user_id = device.get("user_id")
    if current_user_id and str(current_user_id) != str(onboarding_user_id):
        return None, "Device already linked"
    consumed = await consume_onboarding_token(db, device_id, token_hash)
    if not consumed:
        return None, "Onboarding token already used"
    await link_user(db, device_id, str(onboarding_user_id))
    await update_device_metadata(db, device_id, {
        "status": "online",
        "backend_status": "connected",
    })
    return {"device_id": device_id, "status": "online"}, None


async def update_device_status(
    db: AsyncIOMotorDatabase, device_id: str, payload: dict
) -> tuple[Optional[dict], Optional[str]]:
    status = payload.get("status")
    if status not in DEVICE_STATES:
        return None, "Invalid device status"
    updates = {"status": status}
    for key in (
        "wifi_status", "backend_status", "firmware_version",
        "protocol_version", "last_error",
    ):
        if payload.get(key) is not None:
            updates[key] = payload[key]
    await update_device_metadata(db, device_id, updates)
    return {"device_id": device_id, **updates}, None


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
    if not stored_user_id or str(stored_user_id) != user_id:
        return None, "Forbidden"

    return {
        "device_id": device_id,
        "status": device.get("status", "unknown"),
        "last_seen": device.get("last_seen"),
        "wifi_status": device.get("wifi_status", "unknown"),
        "backend_status": device.get("backend_status", "unknown"),
        "firmware_version": device.get("firmware_version"),
        "protocol_version": device.get("protocol_version"),
        "last_error": device.get("last_error"),
        "provisioned_at": device.get("provisioned_at"),
    }, None


async def list_devices(db: AsyncIOMotorDatabase, user_id: str) -> list[dict]:
    devices = await list_by_user(db, user_id)
    return [
        {
            "device_id": device.get("device_id"),
            "status": device.get("status", "unknown"),
            "last_seen": device.get("last_seen"),
            "wifi_status": device.get("wifi_status", "unknown"),
            "backend_status": device.get("backend_status", "unknown"),
            "last_error": device.get("last_error"),
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
