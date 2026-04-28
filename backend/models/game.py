from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class GameDoc(BaseModel):
    id: str = Field(alias="_id")
    players: list[str]
    current_fen: str
    status: str
    game_version: int = 0
    last_move: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        allow_population_by_field_name = True
