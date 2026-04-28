from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class UserDoc(BaseModel):
    id: str = Field(alias="_id")
    email: str
    password_hash: str
    display_name: str
    is_guest: bool = False
    created_at: datetime

    class Config:
        allow_population_by_field_name = True
