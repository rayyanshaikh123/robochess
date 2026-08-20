from typing import Any, Optional

import requests

from pi_agent.config import API_BASE_URL


class DeviceApiClient:
    def __init__(self, base_url: str = API_BASE_URL) -> None:
        self.base_url = base_url.rstrip("/")
        self.device_token: Optional[str] = None

    def connect(self, device_id: str, device_secret: str) -> dict[str, Any]:
        response = requests.post(
            f"{self.base_url}/device/connect",
            json={"device_id": device_id, "device_secret": device_secret},
            timeout=10,
        )
        response.raise_for_status()
        data = response.json().get("data", {})
        self.device_token = data.get("device_token")
        return data

    def heartbeat(self, device_id: str) -> None:
        headers = self._auth_headers()
        requests.post(
            f"{self.base_url}/device/heartbeat",
            headers=headers,
            timeout=10,
        ).raise_for_status()

    def claim(self, onboarding_token: str) -> dict[str, Any]:
        response = requests.post(
            f"{self.base_url}/device/claim",
            json={"onboarding_token": onboarding_token},
            headers=self._auth_headers(),
            timeout=10,
        )
        response.raise_for_status()
        return response.json().get("data", {})

    def update_status(self, status: str, **metadata: Any) -> dict[str, Any]:
        payload = {"status": status, **metadata}
        response = requests.post(
            f"{self.base_url}/device/status",
            json=payload,
            headers=self._auth_headers(),
            timeout=10,
        )
        response.raise_for_status()
        return response.json().get("data", {})

    def request_ble_token(self) -> dict[str, Any]:
        headers = self._auth_headers()
        response = requests.post(
            f"{self.base_url}/device/ble/token",
            headers=headers,
            timeout=10,
        )
        response.raise_for_status()
        return response.json().get("data", {})

    def submit_move(self, game_id: str, uci: str, expected_version: Optional[int]) -> dict:
        payload = {"game_id": game_id, "uci": uci, "expected_version": expected_version}
        response = requests.post(
            f"{self.base_url}/game/move",
            json=payload,
            timeout=10,
        )
        response.raise_for_status()
        return response.json().get("data", {})

    def sync_session(self, session: dict) -> dict[str, Any]:
        """Upload the Pi-authoritative session history when backend access returns.

        The companion backend endpoint must deduplicate by ``session_id`` and
        ``state_hash``; conflicts are returned, never silently merged.
        """
        response = requests.post(
            f"{self.base_url}/device/session/sync", json=session,
            headers=self._auth_headers(), timeout=10,
        )
        response.raise_for_status()
        return response.json().get("data", {})

    def _auth_headers(self) -> dict[str, str]:
        if not self.device_token:
            return {}
        return {"Authorization": f"Bearer {self.device_token}"}
