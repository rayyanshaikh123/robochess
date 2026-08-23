"""Event names and broadcast helpers for the social/multiplayer feature.

Keeping the names here stops them drifting between the routers that emit them
and the client that switches on them. The envelope is the existing
``{"type": ..., "data": {...}}`` used by the rest of the socket layer.
"""

from typing import Any, Optional

from backend.realtime.manager import manager

# Friends
FRIEND_REQUEST_RECEIVED = "friend.request.received"
FRIEND_REQUEST_ACCEPTED = "friend.request.accepted"
FRIEND_REQUEST_REJECTED = "friend.request.rejected"
FRIEND_REQUEST_CANCELLED = "friend.request.cancelled"
FRIEND_REMOVED = "friend.removed"

# Challenges
CHALLENGE_RECEIVED = "challenge.received"
CHALLENGE_ACCEPTED = "challenge.accepted"
CHALLENGE_REJECTED = "challenge.rejected"
CHALLENGE_CANCELLED = "challenge.cancelled"

# Games
GAME_CREATED = "game.created"
GAME_MOVE = "game.move"
GAME_OVER = "game.over"
GAME_CHAT = "game.chat"
GAME_CLOCK = "game.clock"
GAME_DRAW_OFFERED = "game.draw.offered"
GAME_DRAW_ACCEPTED = "game.draw.accepted"
GAME_DRAW_REJECTED = "game.draw.rejected"
PLAYER_JOINED = "player.joined"
PLAYER_LEFT = "player.left"


def device_room(device_id: str) -> str:
    """Matches the room name the device socket path already subscribes to."""
    return f"device:{device_id}"


async def notify_user(user_id: Optional[str], event: str, data: dict[str, Any]) -> None:
    if not user_id:
        return
    await manager.send_to_user(user_id, {"type": event, "data": data})


async def notify_game(game_id: str, event: str, data: dict[str, Any]) -> None:
    await manager.send_to_game(game_id, {"type": event, "data": data})


async def notify_device(device_id: str, event: str, data: dict[str, Any]) -> None:
    await manager.send_to_game(device_room(device_id), {"type": event, "data": data})


async def broadcast_move(game: dict, move_data: dict[str, Any]) -> None:
    """Send a move to the game room and to any physical board in the game.

    A board-backed player needs the move on its device channel so the gantry can
    actuate it; an app-backed player just needs the game room.
    """
    game_id = move_data.get("game_id")
    if game_id:
        await notify_game(game_id, GAME_MOVE, move_data)
    surfaces = game.get("surfaces") or {}
    mover_id = move_data.get("user_id")
    for user_id, surface in surfaces.items():
        if surface and surface != "app" and user_id != mover_id:
            await notify_device(surface, GAME_MOVE, move_data)
