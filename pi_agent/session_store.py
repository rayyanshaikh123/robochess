"""Crash-safe local persistence for the Pi-authoritative chess session."""

from __future__ import annotations

import json
import os
from pathlib import Path

from pi_agent.game_session import GameSession


class SessionStore:
    def __init__(self, path: str | None = None) -> None:
        local_default = Path(__file__).with_name(".state") / "session.json"
        self.path = Path(path or os.getenv("ROBOCHESS_SESSION_FILE", str(local_default)))

    def load(self) -> GameSession | None:
        try:
            return GameSession.from_snapshot(json.loads(self.path.read_text()))
        except (FileNotFoundError, json.JSONDecodeError, KeyError, ValueError):
            return None

    def save(self, session: GameSession | None) -> None:
        if session is None:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(session.snapshot(), separators=(",", ":")))
        os.chmod(temporary, 0o600)
        temporary.replace(self.path)
