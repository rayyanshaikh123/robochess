from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class PuzzleDoc(BaseModel):
    id: str = Field(alias="_id")
    fen: str
    solution: list[str]
    rating: Optional[int] = None
    tags: list[str] = []
    created_at: datetime

    class Config:
        allow_population_by_field_name = True
