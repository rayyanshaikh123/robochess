from collections import defaultdict
from typing import Any

from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self._rooms: dict[str, set[WebSocket]] = defaultdict(set)
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
