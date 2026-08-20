import os
from pathlib import Path


def _load_local_env() -> None:
    """Load pi_agent/.env for direct local runs without overriding systemd env."""
    path = Path(__file__).with_name(".env")
    try:
        for raw_line in path.read_text().splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    except FileNotFoundError:
        pass


_load_local_env()


def _get_env(key: str, default: str) -> str:
    value = os.getenv(key)
    return value.strip() if value else default


def _get_env_bool(key: str, default: str = "0") -> bool:
    value = _get_env(key, default).lower()
    return value in {"1", "true", "yes", "on"}


API_BASE_URL = _get_env("ROBOCHESS_API_BASE", "http://localhost:8000")
WS_BASE_URL = _get_env("ROBOCHESS_WS_BASE", "ws://localhost:8000/ws")
DEVICE_ID = _get_env("ROBOCHESS_DEVICE_ID", "")
DEVICE_SECRET = _get_env("ROBOCHESS_DEVICE_SECRET", "")
HEARTBEAT_SECONDS = int(_get_env("ROBOCHESS_HEARTBEAT_SECONDS", "10"))
BLE_ENABLED = _get_env_bool("ROBOCHESS_BLE_ENABLED", "0")
BLE_ADVERTISE_MODE = _get_env("ROBOCHESS_BLE_ADVERTISE_MODE", "bluez")
BLE_ADAPTER = _get_env("ROBOCHESS_BLE_ADAPTER", "")
BLE_NAME = _get_env("ROBOCHESS_BLE_NAME", "")
BLE_SERVICE_UUID = _get_env(
    "ROBOCHESS_BLE_SERVICE_UUID",
    "0000f00d-0000-1000-8000-00805f9b34fb",
)
BLE_TOKEN_REFRESH_SECONDS = int(_get_env("ROBOCHESS_BLE_TOKEN_REFRESH_SECONDS", "120"))
STOCKFISH_PATH = _get_env("ROBOCHESS_STOCKFISH_PATH", "stockfish")
ENGINE_TIME_SECONDS = float(_get_env("ROBOCHESS_ENGINE_TIME", "0.50"))
ENGINE_SKILL_LEVEL = int(_get_env("ROBOCHESS_ENGINE_SKILL_LEVEL", "10"))
UNO_PORT = _get_env("ROBOCHESS_UNO_PORT", "")
UNO_BAUDRATE = int(_get_env("ROBOCHESS_UNO_BAUDRATE", "115200"))
UNO_TIMEOUT_SECONDS = float(_get_env("ROBOCHESS_UNO_TIMEOUT_SECONDS", "8"))
UNO_SIMULATOR = _get_env_bool("ROBOCHESS_UNO_SIMULATOR", "1")
