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
BLE_REQUIRE_BOND = _get_env_bool("ROBOCHESS_BLE_REQUIRE_BOND", "0")
BLE_ADVERTISE_MODE = _get_env("ROBOCHESS_BLE_ADVERTISE_MODE", "bluez")
BLE_ADAPTER = _get_env("ROBOCHESS_BLE_ADAPTER", "")
BLE_NAME = _get_env("ROBOCHESS_BLE_NAME", "")
BLE_SERVICE_UUID = _get_env(
    "ROBOCHESS_BLE_SERVICE_UUID",
    "0000f00d-0000-1000-8000-00805f9b34fb",
)
BLE_RX_UUID = _get_env(
    "ROBOCHESS_BLE_RX_UUID",
    "0000f00e-0000-1000-8000-00805f9b34fb",
)
BLE_TX_UUID = _get_env(
    "ROBOCHESS_BLE_TX_UUID",
    "0000f00f-0000-1000-8000-00805f9b34fb",
)
BLE_STATUS_UUID = _get_env(
    "ROBOCHESS_BLE_STATUS_UUID",
    "0000f010-0000-1000-8000-00805f9b34fb",
)
BLE_TOKEN_REFRESH_SECONDS = int(_get_env("ROBOCHESS_BLE_TOKEN_REFRESH_SECONDS", "120"))
STOCKFISH_PATH = _get_env("ROBOCHESS_STOCKFISH_PATH", "stockfish")
ENGINE_TIME_SECONDS = float(_get_env("ROBOCHESS_ENGINE_TIME", "0.50"))
ENGINE_SKILL_LEVEL = int(_get_env("ROBOCHESS_ENGINE_SKILL_LEVEL", "10"))
UNO_PORT = _get_env("ROBOCHESS_UNO_PORT", "")
UNO_BAUDRATE = int(_get_env("ROBOCHESS_UNO_BAUDRATE", "115200"))
UNO_TIMEOUT_SECONDS = float(_get_env("ROBOCHESS_UNO_TIMEOUT_SECONDS", "8"))
UNO_SIMULATOR = _get_env_bool("ROBOCHESS_UNO_SIMULATOR", "1")
LOCAL_API_HOST = _get_env("ROBOCHESS_LOCAL_API_HOST", "0.0.0.0")
LOCAL_API_PORT = int(_get_env("ROBOCHESS_LOCAL_API_PORT", "8765"))
LOCAL_STATE_PATH = _get_env("ROBOCHESS_LOCAL_STATE_PATH", "/var/lib/robochess/state")
CAMERA_INDEX = int(_get_env("ROBOCHESS_CAMERA_INDEX", "0"))
CAMERA_WIDTH = int(_get_env("ROBOCHESS_CAPTURE_WIDTH", "800"))
CAMERA_HEIGHT = int(_get_env("ROBOCHESS_CAPTURE_HEIGHT", "600"))
CAMERA_JPEG_QUALITY = int(_get_env("ROBOCHESS_CAMERA_JPEG_QUALITY", "80"))
MODEL_PATH = _get_env("ROBOCHESS_MODEL_PATH", "")
DETECTION_CONFIDENCE = float(_get_env("ROBOCHESS_DET_CONF", "0.10"))
AUTO_DETECT_ENABLED = _get_env_bool("ROBOCHESS_AUTO_DETECT_ENABLED", "1")
DETECT_INTERVAL_SECONDS = float(_get_env("ROBOCHESS_DETECT_INTERVAL_SECONDS", "0.35"))
STABLE_LABEL_COUNT = int(_get_env("ROBOCHESS_STABLE_LABEL_COUNT", "3"))
INTERNET_CHECK_ENABLED = _get_env_bool("ROBOCHESS_INTERNET_CHECK_ENABLED", "1")
INTERNET_CHECK_URL = _get_env(
    "ROBOCHESS_INTERNET_CHECK_URL",
    "https://connectivitycheck.gstatic.com/generate_204",
)
INTERNET_CHECK_TIMEOUT_SECONDS = float(
    _get_env("ROBOCHESS_INTERNET_CHECK_TIMEOUT_SECONDS", "5")
)
INTERNET_CHECK_INTERVAL_SECONDS = int(
    _get_env("ROBOCHESS_INTERNET_CHECK_INTERVAL_SECONDS", "30")
)
VISION_MODE = _get_env("ROBOCHESS_VISION_MODE", "auto").lower()
ROBOFLOW_MODEL_URL = _get_env(
    "ROBOCHESS_ROBOFLOW_MODEL_URL",
    _get_env("ROBOFLOW_MODEL_URL", ""),
)
ROBOFLOW_API_KEY = _get_env(
    "ROBOCHESS_ROBOFLOW_API_KEY",
    _get_env("ROBOFLOW_API_KEY", ""),
)
ROBOFLOW_ENABLED = _get_env_bool("ROBOCHESS_ROBOFLOW_ENABLED", "0")
if not ROBOFLOW_ENABLED and ROBOFLOW_MODEL_URL and ROBOFLOW_API_KEY:
    ROBOFLOW_ENABLED = True
if VISION_MODE == "cloud":
    ROBOFLOW_ENABLED = True
ROBOFLOW_TIMEOUT_SECONDS = float(_get_env("ROBOCHESS_ROBOFLOW_TIMEOUT_SECONDS", "20"))
ROBOFLOW_RETRIES = int(_get_env("ROBOCHESS_ROBOFLOW_RETRIES", "0"))
