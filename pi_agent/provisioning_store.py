"""Small restrictive local store for provisioning state."""

import json
import os
from pathlib import Path


class ProvisioningStore:
    def __init__(self, path: str | None = None) -> None:
        self.path = Path(path or os.getenv("ROBOCHESS_PROVISIONING_FILE", "/var/lib/robochess/provisioning.json"))

    def load(self) -> dict:
        try:
            return json.loads(self.path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def save(self, values: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(values, indent=2))
        os.chmod(self.path, 0o600)

    def set_credentials(self, device_id: str, device_secret: str) -> None:
        values = self.load()
        values["device_id"] = device_id
        values["device_secret"] = device_secret
        self.save(values)

    def get_credentials(self) -> tuple[str | None, str | None]:
        values = self.load()
        device_id = values.get("device_id")
        device_secret = values.get("device_secret")
        return (
            device_id if isinstance(device_id, str) and device_id else None,
            device_secret if isinstance(device_secret, str) and device_secret else None,
        )

    def set_onboarding_token(self, token: str) -> None:
        values = self.load()
        values["onboarding_token"] = token
        self.save(values)

    def clear_onboarding_token(self) -> None:
        values = self.load()
        values.pop("onboarding_token", None)
        self.save(values)
