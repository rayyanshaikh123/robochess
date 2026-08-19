import os


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
