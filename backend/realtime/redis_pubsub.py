import asyncio
import json
from typing import Optional
from uuid import uuid4

import redis.asyncio as redis


class RedisPubSub:
    def __init__(self, redis_url: str, channel: str, manager) -> None:
        self.redis_url = redis_url
        self.channel = channel
        self.manager = manager
        self.instance_id = str(uuid4())
        self._client: Optional[redis.Redis] = None
        self._pubsub = None
        self._task: Optional[asyncio.Task] = None

    async def start(self) -> None:
        self._client = redis.from_url(self.redis_url, decode_responses=True)
        self._pubsub = self._client.pubsub()
        await self._pubsub.subscribe(self.channel)
        self._task = asyncio.create_task(self._listen())

    async def _listen(self) -> None:
        if not self._pubsub:
            return
        async for message in self._pubsub.listen():
            if message.get("type") != "message":
                continue
            try:
                payload = json.loads(message.get("data", "{}"))
            except Exception:
                continue
            if payload.get("source") == self.instance_id:
                continue
            game_id = payload.get("game_id")
            data = payload.get("payload")
            if game_id and data:
                await self.manager.send_to_game_local(game_id, data)

    async def publish(self, game_id: str, payload: dict) -> None:
        if not self._client:
            return
        message = json.dumps(
            {"source": self.instance_id, "game_id": game_id, "payload": payload}
        )
        await self._client.publish(self.channel, message)

    async def close(self) -> None:
        if self._task:
            self._task.cancel()
        if self._pubsub:
            await self._pubsub.close()
        if self._client:
            await self._client.close()
