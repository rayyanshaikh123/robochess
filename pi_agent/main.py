import time

from pi_agent.api_client import DeviceApiClient
from pi_agent.ble_advertiser import create_ble_advertiser
from pi_agent.ble_worker import BleTokenWorker
from pi_agent.config import (
    BLE_ADVERTISE_MODE,
    BLE_ENABLED,
    BLE_SERVICE_UUID,
    BLE_TOKEN_REFRESH_SECONDS,
    DEVICE_ID,
    DEVICE_SECRET,
    HEARTBEAT_SECONDS,
)
from pi_agent.heartbeat import HeartbeatWorker
from pi_agent.vision_adapter import VisionAdapter


def main() -> None:
    if not DEVICE_ID or not DEVICE_SECRET:
        raise RuntimeError("Set ROBOCHESS_DEVICE_ID and ROBOCHESS_DEVICE_SECRET")

    api = DeviceApiClient()
    api.connect(DEVICE_ID, DEVICE_SECRET)

    heartbeat = HeartbeatWorker(api, DEVICE_ID, HEARTBEAT_SECONDS)
    heartbeat.start()

    ble_worker = None
    if BLE_ENABLED:
        advertiser = create_ble_advertiser(BLE_ADVERTISE_MODE, BLE_SERVICE_UUID)
        ble_worker = BleTokenWorker(
            api,
            advertiser,
            BLE_TOKEN_REFRESH_SECONDS,
        )
        ble_worker.start()

    vision = VisionAdapter()

    print("Pi agent running. Waiting for moves...")
    try:
        while True:
            uci, expected_version = vision.detect_move()
            if uci:
                # Game id must be provided by the board controller (e.g. from app start).
                # Replace GAME_ID with your current active game.
                game_id = ""
                if game_id:
                    api.submit_move(game_id, uci, expected_version)
            time.sleep(0.1)
    except KeyboardInterrupt:
        heartbeat.stop()
        if ble_worker:
            ble_worker.stop()


if __name__ == "__main__":
    main()
