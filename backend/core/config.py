from dataclasses import dataclass
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Settings:
    model_path: str
    stockfish_path: str
    camera_index: int
    confidence: float
    engine_time: float
    detection_confidence_min: float
    move_match_min_score: int
    move_match_min_gap: int
    start_max_missing: int
    start_max_extra: int
    capture_width: int
    capture_height: int
    mongodb_uri: str
    mongodb_db: str
    jwt_secret: str
    jwt_algorithm: str
    access_token_minutes: int
    refresh_token_days: int
    device_token_minutes: int
    pairing_code_minutes: int
    ble_pair_token_minutes: int
    local_pairing_code: str
    rate_limit_requests: int
    rate_limit_window_seconds: int
    redis_url: str
    redis_channel: str
    log_level: str


def _get_env_str(key: str, default: str) -> str:
    value = os.getenv(key)
    return value.strip() if value else default


def _get_env_int(key: str, default: int) -> int:
    value = os.getenv(key)
    try:
        return int(value) if value is not None else default
    except Exception:
        return default


def _get_env_float(key: str, default: float) -> float:
    value = os.getenv(key)
    try:
        return float(value) if value is not None else default
    except Exception:
        return default


def load_settings() -> Settings:
    default_model = ROOT / "models" / "best.pt"
    default_stockfish = ROOT / "stockfish" / "stockfish-windows-x86-64-avx2.exe"
    return Settings(
        model_path=_get_env_str("ROBOCHESS_MODEL_PATH", str(default_model)),
        stockfish_path=_get_env_str("ROBOCHESS_STOCKFISH_PATH", str(default_stockfish)),
        camera_index=_get_env_int("ROBOCHESS_CAMERA_INDEX", 0),
        confidence=_get_env_float("ROBOCHESS_CONFIDENCE", 0.05),
        engine_time=_get_env_float("ROBOCHESS_ENGINE_TIME", 0.50),
        detection_confidence_min=_get_env_float("ROBOCHESS_DET_CONF", 0.10),
        move_match_min_score=_get_env_int("ROBOCHESS_MATCH_MIN", 54),
        move_match_min_gap=_get_env_int("ROBOCHESS_MATCH_GAP", 2),
        start_max_missing=_get_env_int("ROBOCHESS_START_MISSING", 16),
        start_max_extra=_get_env_int("ROBOCHESS_START_EXTRA", 6),
        capture_width=_get_env_int("ROBOCHESS_CAPTURE_WIDTH", 820),
        capture_height=_get_env_int("ROBOCHESS_CAPTURE_HEIGHT", 620),
        mongodb_uri=_get_env_str("ROBOCHESS_MONGODB_URI", "mongodb://localhost:27017"),
        mongodb_db=_get_env_str("ROBOCHESS_MONGODB_DB", "robochess"),
        jwt_secret=_get_env_str("ROBOCHESS_JWT_SECRET", "change-me"),
        jwt_algorithm=_get_env_str("ROBOCHESS_JWT_ALG", "HS256"),
        access_token_minutes=_get_env_int("ROBOCHESS_ACCESS_MINUTES", 30),
        refresh_token_days=_get_env_int("ROBOCHESS_REFRESH_DAYS", 30),
        device_token_minutes=_get_env_int("ROBOCHESS_DEVICE_TOKEN_MINUTES", 1440),
        pairing_code_minutes=_get_env_int("ROBOCHESS_PAIRING_CODE_MINUTES", 5),
        ble_pair_token_minutes=_get_env_int("ROBOCHESS_BLE_PAIR_MINUTES", 5),
        local_pairing_code=_get_env_str("ROBOCHESS_LOCAL_PAIR_CODE", "000000"),
        rate_limit_requests=_get_env_int("ROBOCHESS_RATE_LIMIT_REQUESTS", 60),
        rate_limit_window_seconds=_get_env_int("ROBOCHESS_RATE_LIMIT_WINDOW", 60),
        redis_url=_get_env_str("ROBOCHESS_REDIS_URL", ""),
        redis_channel=_get_env_str("ROBOCHESS_REDIS_CHANNEL", "robochess_ws"),
        log_level=_get_env_str("ROBOCHESS_LOG_LEVEL", "INFO"),
    )
