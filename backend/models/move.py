from datetime import datetime

from pydantic import BaseModel, Field


class MoveDoc(BaseModel):
    id: str = Field(alias="_id")
    game_id: str
    move_number: int
    uci: str
    fen_after: str
    created_at: datetime

    class Config:
        allow_population_by_field_name = True
