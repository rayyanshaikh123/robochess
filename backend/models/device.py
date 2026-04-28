from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class DeviceDoc(BaseModel):
    id: str = Field(alias="_id")
    device_id: str
    device_secret_hash: str
    user_id: Optional[str] = None
    status: str = "disconnected"
    created_at: datetime
    last_seen: Optional[datetime] = None
    pairing_code: Optional[str] = None
    pairing_expires_at: Optional[datetime] = None
    ble_pair_token: Optional[str] = None
    ble_pair_expires_at: Optional[datetime] = None

    class Config:
        allow_population_by_field_name = True
