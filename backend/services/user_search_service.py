"""Friend discovery.

Results carry only what the UI needs to identify a player plus the caller's
existing relationship to them. Email is accepted as an exact-match *input* but
is never returned, so search cannot be used to harvest addresses.
"""

from typing import Optional

from motor.motor_asyncio import AsyncIOMotorDatabase

from backend.repositories.user_repo import search_users
from backend.services.friendship_service import relationship_map

MIN_QUERY_LENGTH = 2


async def search(
    db: AsyncIOMotorDatabase, user_id: str, query: str, limit: int = 20
) -> tuple[Optional[dict], Optional[str]]:
    term = (query or "").strip()
    if len(term) < MIN_QUERY_LENGTH:
        return None, f"Enter at least {MIN_QUERY_LENGTH} characters to search"

    rows = await search_users(db, term, exclude_user_id=user_id, limit=limit)
    ids = [str(row["_id"]) for row in rows]
    relationships = await relationship_map(db, user_id, ids)

    items = []
    for row in rows:
        other_id = str(row["_id"])
        relationship = relationships.get(other_id)
        items.append(
            {
                "user_id": other_id,
                "display_name": row.get("display_name") or "Player",
                "rating": row.get("rating"),
                "friend_status": (relationship or {}).get("status"),
                "friendship_id": (relationship or {}).get("friendship_id"),
                "requested_by_me": (relationship or {}).get("requested_by_me"),
            }
        )
    return {"items": items}, None
