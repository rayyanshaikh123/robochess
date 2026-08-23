"""Friend requests and friendships.

Every function returns the codebase's ``(data, error)`` tuple and never raises.
Authorization is enforced here rather than in the router: only the addressee may
accept or reject, only the requester may cancel, and only a participant may
unfriend.
"""

from typing import Optional

from motor.motor_asyncio import AsyncIOMotorDatabase
from pymongo.errors import DuplicateKeyError

from backend.repositories.friendship_repo import (
    ACCEPTED,
    PENDING,
    REJECTED,
    create_friendship,
    delete_friendship,
    get_between,
    get_by_id,
    list_by_status,
    list_requests,
    reopen_request,
    set_status,
    statuses_for,
)
from backend.repositories.user_repo import get_many_by_ids


def _public_user(user: Optional[dict]) -> dict:
    """The only user shape that leaves this service.

    Email and password hash are deliberately excluded — a friends list must not
    become a directory of addresses.
    """
    if not user:
        return {"user_id": "", "display_name": "Unknown player", "rating": None}
    return {
        "user_id": str(user.get("_id")),
        "display_name": user.get("display_name") or "Player",
        "rating": user.get("rating"),
    }


def _other_id(row: dict, user_id: str) -> str:
    return row["user_b"] if row["user_a"] == user_id else row["user_a"]


def _serialize(row: dict, user_id: str, profiles: dict) -> dict:
    other = _other_id(row, user_id)
    created = row.get("created_at")
    updated = row.get("updated_at")
    return {
        "friendship_id": str(row["_id"]),
        "status": row.get("status"),
        "user": _public_user(profiles.get(other)),
        "requested_by_me": row.get("requester_id") == user_id,
        "created_at": created.isoformat() if created else None,
        "updated_at": updated.isoformat() if updated else None,
    }


async def _hydrate(db, rows: list[dict], user_id: str) -> list[dict]:
    others = [_other_id(row, user_id) for row in rows]
    profiles = await get_many_by_ids(db, others)
    return [_serialize(row, user_id, profiles) for row in rows]


async def send_request(
    db: AsyncIOMotorDatabase, user_id: str, target_user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    if not target_user_id:
        return None, "Target user is required"
    if target_user_id == user_id:
        return None, "You cannot send a friend request to yourself"

    targets = await get_many_by_ids(db, [target_user_id])
    target = targets.get(target_user_id)
    if target is None:
        return None, "User not found"

    existing = await get_between(db, user_id, target_user_id)
    if existing is not None:
        status = existing.get("status")
        if status == ACCEPTED:
            return None, "You are already friends"
        if status == PENDING:
            # The mirrored request already exists, so this is really an accept.
            if existing.get("requester_id") == target_user_id:
                await set_status(db, str(existing["_id"]), ACCEPTED, expected_status=PENDING)
                fresh = await get_by_id(db, str(existing["_id"]))
                data = _serialize(fresh or existing, user_id, {target_user_id: target})
                data["auto_accepted"] = True
                return data, None
            return None, "Friend request already pending"
        if status == REJECTED:
            reopened = await reopen_request(
                db, str(existing["_id"]), user_id, target_user_id
            )
            if not reopened:
                return None, "Could not resend the friend request"
            fresh = await get_by_id(db, str(existing["_id"]))
            return _serialize(fresh or existing, user_id, {target_user_id: target}), None

    try:
        row = await create_friendship(db, user_id, target_user_id, PENDING)
    except DuplicateKeyError:
        # Someone created the mirrored row between our read and write.
        return None, "Friend request already pending"
    return _serialize(row, user_id, {target_user_id: target}), None


async def respond_to_request(
    db: AsyncIOMotorDatabase, user_id: str, friendship_id: str, accept: bool
) -> tuple[Optional[dict], Optional[str]]:
    row = await get_by_id(db, friendship_id)
    if row is None:
        return None, "Friend request not found"
    if row.get("status") != PENDING:
        return None, "Friend request is no longer pending"
    if row.get("addressee_id") != user_id:
        return None, "Not authorized"

    status = ACCEPTED if accept else REJECTED
    changed = await set_status(db, friendship_id, status, expected_status=PENDING)
    if not changed:
        return None, "Friend request is no longer pending"

    other = _other_id(row, user_id)
    profiles = await get_many_by_ids(db, [other])
    fresh = await get_by_id(db, friendship_id)
    return _serialize(fresh or row, user_id, profiles), None


async def cancel_request(
    db: AsyncIOMotorDatabase, user_id: str, friendship_id: str
) -> tuple[Optional[dict], Optional[str]]:
    row = await get_by_id(db, friendship_id)
    if row is None:
        return None, "Friend request not found"
    if row.get("status") != PENDING:
        return None, "Friend request is no longer pending"
    if row.get("requester_id") != user_id:
        return None, "Not authorized"
    if not await delete_friendship(db, friendship_id):
        return None, "Could not cancel the friend request"
    return {"friendship_id": friendship_id, "cancelled": True,
            "user_id": _other_id(row, user_id)}, None


async def remove_friend(
    db: AsyncIOMotorDatabase, user_id: str, other_user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    row = await get_between(db, user_id, other_user_id)
    if row is None or row.get("status") != ACCEPTED:
        return None, "You are not friends with this user"
    if user_id not in (row.get("user_a"), row.get("user_b")):
        return None, "Not authorized"
    if not await delete_friendship(db, str(row["_id"])):
        return None, "Could not remove the friend"
    return {"user_id": other_user_id, "removed": True}, None


async def list_friends(
    db: AsyncIOMotorDatabase, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    rows = await list_by_status(db, user_id, ACCEPTED)
    return {"items": await _hydrate(db, rows, user_id)}, None


async def list_incoming_requests(
    db: AsyncIOMotorDatabase, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    rows = await list_requests(db, user_id, incoming=True)
    return {"items": await _hydrate(db, rows, user_id)}, None


async def list_outgoing_requests(
    db: AsyncIOMotorDatabase, user_id: str
) -> tuple[Optional[dict], Optional[str]]:
    rows = await list_requests(db, user_id, incoming=False)
    return {"items": await _hydrate(db, rows, user_id)}, None


async def relationship_map(
    db: AsyncIOMotorDatabase, user_id: str, other_ids: list[str]
) -> dict[str, dict]:
    """Relationship metadata per other-user id, used to annotate search hits."""
    rows = await statuses_for(db, user_id, other_ids)
    annotated: dict[str, dict] = {}
    for other, row in rows.items():
        annotated[other] = {
            "friendship_id": str(row["_id"]),
            "status": row.get("status"),
            "requested_by_me": row.get("requester_id") == user_id,
        }
    return annotated
