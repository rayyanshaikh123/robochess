from dataclasses import dataclass
import os
from pathlib import Path
from dotenv import load_dotenv

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")

# Load .env from backend folder or project root
load_dotenv(ROOT / ".env")
load_dotenv(ROOT / "backend" / ".env")


def _get_env_sf_path() -> str:
    """Check for several environment variable names for stockfish path."""
    for key in ["ROBOCHESS_STOCKFISH_PATH", "STOCKFISH_PATH"]:
        val = os.getenv(key, "").strip()
        if val and Path(val).is_file():
            return val
    return ""


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


def _find_stockfish() -> str:
    """Try to auto-discover Stockfish from common install locations."""
    import shutil

    # 1. Check env vars first
    env_path = _get_env_sf_path()
    if env_path:
        return env_path

    # 2. Canonical project-local path
    candidates = [
        ROOT / "stockfish" / "stockfish-windows-x86-64-avx2.exe",
        ROOT / "stockfish" / "stockfish.exe",
        ROOT / "stockfish" / "stockfish",
        # One level up (repo root)
        ROOT.parent / "stockfish" / "stockfish-windows-x86-64-avx2.exe",
        ROOT.parent / "stockfish" / "stockfish.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)

    # 3. System PATH (works if installed via winget / package manager)
    system_sf = shutil.which("stockfish")
    if system_sf:
        return system_sf

    # 4. Common Windows install locations
    win_candidates = [
        Path(r"C:\Program Files\Stockfish\stockfish.exe"),
        Path(r"C:\Program Files\Stockfish\stockfish-windows-x86-64-avx2.exe"),
        Path(os.path.expanduser(r"~\scoop\apps\stockfish\current\stockfish.exe")),
    ]
    for candidate in win_candidates:
        if candidate.is_file():
            return str(candidate)

    # Fall back to the default project path (will fail gracefully at runtime)
    return str(ROOT / "stockfish" / "stockfish-windows-x86-64-avx2.exe")


def load_settings() -> Settings:
    default_model = ROOT / "models" / "best.pt"
    default_stockfish = _find_stockfish()
    return Settings(
        model_path=_get_env_str("ROBOCHESS_MODEL_PATH", str(default_model)),
        stockfish_path=default_stockfish,
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
