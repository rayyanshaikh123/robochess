from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class RefreshTokenDoc(BaseModel):
    id: str = Field(alias="_id")
    user_id: str
    device_id: Optional[str] = None
    token_hash: str
    expires_at: datetime
    revoked: bool = False
    created_at: datetime
    revoked_at: Optional[datetime] = None

    class Config:
        allow_population_by_field_name = True
