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

    def set_onboarding_token(self, token: str) -> None:
        values = self.load()
        values["onboarding_token"] = token
        self.save(values)
