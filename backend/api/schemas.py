from typing import Any, Optional

from pydantic import BaseModel, Field


class ApiResponse(BaseModel):
    status: str
    message: str
    data: Optional[dict[str, Any]] = None


class GameStartRequest(BaseModel):
    mode: str = Field(default="human_vs_ai")
    difficulty: int = Field(default=5, ge=1, le=10)
    players: Optional[list[str]] = None


class MoveAiRequest(BaseModel):
    difficulty: Optional[int] = Field(default=None, ge=1, le=10)


class RegisterRequest(BaseModel):
    email: str
    password: str = Field(min_length=8)
    display_name: Optional[str] = Field(default=None, min_length=1, max_length=64)
    device_id: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str = Field(min_length=8)
    device_id: Optional[str] = None


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10)


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=10)


class DeviceRegisterRequest(BaseModel):
    hardware_id: Optional[str] = None


class DeviceLinkRequest(BaseModel):
    pairing_code: str = Field(min_length=4, max_length=12)


class DeviceBleLinkRequest(BaseModel):
    token: str = Field(min_length=8, max_length=64)


class DeviceOnboardingRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)


class DeviceClaimRequest(BaseModel):
    onboarding_token: str = Field(min_length=16, max_length=256)


class DeviceStatusUpdateRequest(BaseModel):
    status: str = Field(min_length=1, max_length=32)
    wifi_status: Optional[str] = Field(default=None, max_length=32)
    backend_status: Optional[str] = Field(default=None, max_length=32)
    firmware_version: Optional[str] = Field(default=None, max_length=64)
    protocol_version: Optional[str] = Field(default=None, max_length=32)
    last_error: Optional[str] = Field(default=None, max_length=512)


class BoardSessionSyncRequest(BaseModel):
    session_id: str = Field(min_length=1, max_length=128)
    initial_fen: str = Field(min_length=1, max_length=256)
    moves: list[str] = Field(default_factory=list, max_length=1000)
    version: int = Field(ge=0)
    state_hash: str = Field(min_length=16, max_length=128)
    fen: Optional[str] = Field(default=None, max_length=256)
    phase: Optional[str] = Field(default=None, max_length=64)
    game_over: bool = False
    result: Optional[str] = Field(default=None, max_length=32)


class DeviceConnectRequest(BaseModel):
    device_id: str
    device_secret: str


class GameMoveRequest(BaseModel):
    game_id: str
    uci: str
    expected_version: Optional[int] = None


class PuzzleAttemptRequest(BaseModel):
    puzzle_id: str
    uci: str
    move_index: int = Field(ge=0)


class ModelLoadRequest(BaseModel):
    model_path: Optional[str] = None


class ManualCalibrationRequest(BaseModel):
    corners: list[list[float]]
