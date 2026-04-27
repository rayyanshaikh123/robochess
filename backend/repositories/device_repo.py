from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.db.collections import DEVICES


async def create_device(
    db: AsyncIOMotorDatabase,
    device_id: str,
    device_secret_hash: str,
    pairing_code: str,
    pairing_expires_at,
    hardware_id: Optional[str] = None,
) -> dict:
    now = datetime.now(timezone.utc)
    doc = {
        "device_id": device_id,
        "device_secret_hash": device_secret_hash,
        "pairing_code": pairing_code,
        "pairing_expires_at": pairing_expires_at,
        "ble_pair_token": None,
        "ble_pair_expires_at": None,
        "hardware_id": hardware_id,
        "user_id": None,
        "status": "disconnected",
        "created_at": now,
        "last_seen": None,
    }
    result = await db[DEVICES].insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


async def get_by_device_id(db: AsyncIOMotorDatabase, device_id: str) -> Optional[dict]:
    return await db[DEVICES].find_one({"device_id": device_id})


async def get_by_hardware_id(db: AsyncIOMotorDatabase, hardware_id: str) -> Optional[dict]:
    return await db[DEVICES].find_one({"hardware_id": hardware_id})


async def get_by_pairing_code(db: AsyncIOMotorDatabase, pairing_code: str) -> Optional[dict]:
    return await db[DEVICES].find_one({"pairing_code": pairing_code})


async def get_by_ble_pair_token(db: AsyncIOMotorDatabase, token: str) -> Optional[dict]:
    return await db[DEVICES].find_one({"ble_pair_token": token})


async def link_user(db: AsyncIOMotorDatabase, device_id: str, user_id: str) -> None:
    await db[DEVICES].update_one(
        {"device_id": device_id},
        {
            "$set": {
                "user_id": ObjectId(user_id),
                "pairing_code": None,
                "pairing_expires_at": None,
                "ble_pair_token": None,
                "ble_pair_expires_at": None,
            }
        },
    )


async def update_ble_pair_token(
    db: AsyncIOMotorDatabase,
    device_id: str,
    token: str,
    expires_at,
) -> None:
    await db[DEVICES].update_one(
        {"device_id": device_id},
        {"$set": {"ble_pair_token": token, "ble_pair_expires_at": expires_at}},
    )


async def update_status(db: AsyncIOMotorDatabase, device_id: str, status: str) -> None:
    now = datetime.now(timezone.utc)
    await db[DEVICES].update_one(
        {"device_id": device_id},
        {"$set": {"status": status, "last_seen": now}},
    )


async def list_by_user(db: AsyncIOMotorDatabase, user_id: str) -> list[dict]:
    cursor = db[DEVICES].find({"user_id": ObjectId(user_id)}).sort("created_at", -1)
    return await cursor.to_list(length=200)


async def unlink_by_user(db: AsyncIOMotorDatabase, user_id: str, device_id: str) -> bool:
    result = await db[DEVICES].update_one(
        {"device_id": device_id, "user_id": ObjectId(user_id)},
        {"$set": {"user_id": None, "status": "disconnected"}},
    )
    return result.modified_count == 1


async def restore_pairing_code(
    db: AsyncIOMotorDatabase,
    device_id: str,
    pairing_code: str,
    pairing_expires_at,
) -> None:
    await db[DEVICES].update_one(
        {"device_id": device_id},
        {
            "$set": {
                "pairing_code": pairing_code,
                "pairing_expires_at": pairing_expires_at,
            }
        },
    )
