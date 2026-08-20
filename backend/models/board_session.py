from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class BoardSessionDoc(BaseModel):
    """Pi-authoritative physical-board session; intentionally separate from GameDoc."""

    device_id: str
    session_id: str
    initial_fen: str
    moves: list[str]
    version: int = Field(ge=0)
    state_hash: str
    fen: str
    phase: Optional[str] = None
    game_over: bool = False
    result: Optional[str] = None
    created_at: datetime
    updated_at: datetime
