from collections import defaultdict
from typing import Any

from fastapi import WebSocket


def user_room(user_id: str) -> str:
    """Room every connection of one user joins, for events not tied to a game."""
    return f"user:{user_id}"


class ConnectionManager:
    def __init__(self) -> None:
        self._rooms: dict[str, set[WebSocket]] = defaultdict(set)
        self._socket_user: dict[WebSocket, str] = {}
        self._pubsub = None

    def set_pubsub(self, pubsub) -> None:
        self._pubsub = pubsub

    async def connect(self, game_id: str, websocket: WebSocket) -> None:
        self._rooms[game_id].add(websocket)

    def disconnect(self, game_id: str, websocket: WebSocket) -> None:
        room = self._rooms.get(game_id)
        if not room:
            return
        room.discard(websocket)
        if not room:
            self._rooms.pop(game_id, None)

    # -- identity -------------------------------------------------------------

    def bind_user(self, websocket: WebSocket, user_id: str) -> None:
        """Remember who a socket belongs to and subscribe it to its user room."""
        self._socket_user[websocket] = user_id
        self._rooms[user_room(user_id)].add(websocket)

    def unbind_user(self, websocket: WebSocket) -> None:
        user_id = self._socket_user.pop(websocket, None)
        if user_id is not None:
            self.disconnect(user_room(user_id), websocket)

    def user_for(self, websocket: WebSocket) -> str | None:
        return self._socket_user.get(websocket)

    def is_user_online(self, user_id: str) -> bool:
        return bool(self._rooms.get(user_room(user_id)))

    async def send_to_user(self, user_id: str, message: dict[str, Any]) -> None:
        """Deliver to every connection of one user, across instances."""
        await self.send_to_game(user_room(user_id), message)

    async def send_to_game_local(self, game_id: str, message: dict[str, Any]) -> None:
        room = list(self._rooms.get(game_id, set()))
        for socket in room:
            try:
                await socket.send_json(message)
            except Exception:
                self.disconnect(game_id, socket)

    async def send_to_game(self, game_id: str, message: dict[str, Any]) -> None:
        await self.send_to_game_local(game_id, message)
        if self._pubsub is not None:
            await self._pubsub.publish(game_id, message)


manager = ConnectionManager()
