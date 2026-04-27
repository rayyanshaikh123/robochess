import os


def get_env(key: str, default: str) -> str:
    value = os.getenv(key)
    return value.strip() if value else default


API_BASE_URL = get_env("ROBOCHESS_API_BASE", "http://localhost:8000")
WS_BASE_URL = get_env("ROBOCHESS_WS_BASE", "ws://localhost:8000/ws")
DEVICE_ID = get_env("ROBOCHESS_DEVICE_ID", "")
DEVICE_SECRET = get_env("ROBOCHESS_DEVICE_SECRET", "")
HARDWARE_ID = get_env("ROBOCHESS_HARDWARE_ID", "")
