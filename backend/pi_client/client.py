import asyncio
import json
from typing import Any, Optional

import requests
import websockets

from .config import API_BASE_URL, WS_BASE_URL


class PiClient:
    def __init__(self, api_base: str = API_BASE_URL, ws_base: str = WS_BASE_URL) -> None:
        self.api_base = api_base.rstrip("/")
        self.ws_base = ws_base
        self.device_id: Optional[str] = None
        self.device_secret: Optional[str] = None
        self.device_token: Optional[str] = None
        self.game_id: Optional[str] = None
        self.last_known_version: int = 0

    def register_device(self, hardware_id: Optional[str] = None) -> dict[str, Any]:
        payload = {"hardware_id": hardware_id}
        response = requests.post(f"{self.api_base}/device/register", json=payload, timeout=10)
        response.raise_for_status()
        data = response.json().get("data", {})
        self.device_id = data.get("device_id")
        self.device_secret = data.get("device_secret")
        self.device_token = data.get("device_token")
        return data

    def connect_device(self) -> dict[str, Any]:
        if not self.device_id or not self.device_secret:
            raise RuntimeError("Device credentials missing")
        payload = {"device_id": self.device_id, "device_secret": self.device_secret}
        response = requests.post(f"{self.api_base}/device/connect", json=payload, timeout=10)
        response.raise_for_status()
        data = response.json().get("data", {})
        self.device_token = data.get("device_token")
        return data

    def submit_move(self, game_id: str, uci: str, expected_version: Optional[int] = None) -> dict[str, Any]:
        payload = {"game_id": game_id, "uci": uci, "expected_version": expected_version}
        response = requests.post(f"{self.api_base}/game/move", json=payload, timeout=10)
        response.raise_for_status()
        return response.json().get("data", {})

    async def ws_sync(self, game_id: str, last_known_version: int = 0) -> None:
        self.game_id = game_id
        self.last_known_version = last_known_version
        async with websockets.connect(self.ws_base) as websocket:
            await websocket.send(
                json.dumps(
                    {
                        "type": "hello",
                        "game_id": game_id,
                        "last_known_version": last_known_version,
                    }
                )
            )
            async for message in websocket:
                payload = json.loads(message)
                msg_type = payload.get("type")
                if msg_type == "game.move":
                    data = payload.get("data", {})
                    self.last_known_version = int(data.get("game_version", self.last_known_version))
                elif msg_type == "game.delta":
                    data = payload.get("data", {})
                    self.last_known_version = int(data.get("to_version", self.last_known_version))
                elif msg_type == "game.state":
                    data = payload.get("data", {})
                    self.last_known_version = int(data.get("game_version", self.last_known_version))

    async def resync(self) -> None:
        if not self.game_id:
            return
        async with websockets.connect(self.ws_base) as websocket:
            await websocket.send(
                json.dumps(
                    {
                        "type": "resync",
                        "game_id": self.game_id,
                        "last_known_version": self.last_known_version,
                    }
                )
            )


async def main() -> None:
    client = PiClient()
    print("Pi client ready. Register device or connect using stored secrets.")


if __name__ == "__main__":
    asyncio.run(main())
