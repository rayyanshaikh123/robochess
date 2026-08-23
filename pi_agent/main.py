import time
from pathlib import Path

from pi_agent.api_client import DeviceApiClient
from pi_agent.gatt_server import GattServer
from pi_agent.network_manager import NetworkManager, NetworkManagerError
from pi_agent.provisioning_store import ProvisioningStore
from pi_agent.local_api import start_local_api
from pi_agent.config import (
    BLE_ENABLED,
    BLE_ADAPTER,
    BLE_NAME,
    BLE_REQUIRE_BOND,
    DEVICE_ID,
    DEVICE_SECRET,
    HEARTBEAT_SECONDS,
    LOCAL_API_HOST,
    LOCAL_API_PORT,
    LOCAL_STATE_PATH,
    INTERNET_CHECK_ENABLED,
    INTERNET_CHECK_URL,
    INTERNET_CHECK_TIMEOUT_SECONDS,
    CAMERA_INDEX,
    CAMERA_WIDTH,
    CAMERA_HEIGHT,
    CAMERA_JPEG_QUALITY,
    MODEL_PATH,
    DETECTION_CONFIDENCE,
    AUTO_DETECT_ENABLED,
    DETECT_INTERVAL_SECONDS,
    STABLE_LABEL_COUNT,
)
from pi_agent.heartbeat import HeartbeatWorker
from pi_agent.vision_adapter import VisionAdapter
from pi_agent.camera_detector import PiCameraDetector
from pi_agent.config import (
    ENGINE_SKILL_LEVEL, ENGINE_TIME_SECONDS, STOCKFISH_PATH, UNO_BAUDRATE,
    UNO_PORT, UNO_SIMULATOR, UNO_TIMEOUT_SECONDS,
)
from pi_agent.engine import StockfishEngine
from pi_agent.game_controller import GameController
from pi_agent.uno_controller import SerialTransport, SimulatedTransport, UnoController
from pi_agent.session_store import SessionStore


def main() -> None:
    if not DEVICE_ID:
        raise RuntimeError("Set ROBOCHESS_DEVICE_ID (a stable local board identifier)")

    api = DeviceApiClient()
    network = NetworkManager()
    store = ProvisioningStore()
    network_config = {
        "state_path": LOCAL_STATE_PATH,
        "camera_index": CAMERA_INDEX,
        "width": CAMERA_WIDTH,
        "height": CAMERA_HEIGHT,
        "jpeg_quality": CAMERA_JPEG_QUALITY,
        "internet_check_enabled": INTERNET_CHECK_ENABLED,
        "internet_check_url": INTERNET_CHECK_URL,
        "internet_check_timeout": INTERNET_CHECK_TIMEOUT_SECONDS,
        "backend_available": False,
    }

    def claim_pending_token() -> dict:
        token = store.load().get("onboarding_token")
        if not token:
            return {"status": "no_token"}
        if not api.device_token and DEVICE_SECRET:
            api.connect(DEVICE_ID, DEVICE_SECRET)
        if not api.device_token:
            return {"status": "error", "error": "Pi backend credentials are not configured"}
        result = api.claim(token)
        store.save({})
        network_config["backend_available"] = True
        return {"status": "token_claimed", "device": result}

    def on_control(message: dict) -> dict:
        data = message.get("data") or {}
        token = data.get("onboarding_token")
        if token:
            store.set_onboarding_token(token)
            try:
                result = claim_pending_token()
                if result.get("status") == "error":
                    network_state = network.status(
                        INTERNET_CHECK_ENABLED,
                        INTERNET_CHECK_URL,
                        INTERNET_CHECK_TIMEOUT_SECONDS,
                    )
                    if not network_state.internet_available:
                        return {"status": "token_saved"}
                return result
            except Exception as exc:
                network_state = network.status(
                    INTERNET_CHECK_ENABLED,
                    INTERNET_CHECK_URL,
                    INTERNET_CHECK_TIMEOUT_SECONDS,
                )
                if not network_state.internet_available:
                    return {"status": "token_saved"}
                return {"status": "error", "error": str(exc)}
        if message.get("type") == "network.status":
            return {"status": "network_status", "network": network.status(
                INTERNET_CHECK_ENABLED,
                INTERNET_CHECK_URL,
                INTERNET_CHECK_TIMEOUT_SECONDS,
            ).to_dict() | {"backend_available": api.device_token is not None}}
        return {"status": "ready"}

    def on_wifi(message: dict) -> dict:
        data = message.get("data") or {}
        try:
            api.update_status("provisioning_wifi", wifi_status="connecting") if api.device_token else None
            network.configure(str(data.get("ssid", "")), str(data.get("password", "")))
            result = network.wait_until_connected()
            if not result.connected:
                raise NetworkManagerError(result.error or "Wi-Fi connection failed")
            claim = claim_pending_token()
            if claim.get("status") == "error":
                raise NetworkManagerError(claim.get("error", "Cloud linking failed"))
            if api.device_token:
                api.update_status("wifi_connected", wifi_status="connected")
            return {"status": "wifi_connected", "ssid": result.ssid}
        except Exception as exc:
            if api.device_token:
                try:
                    api.update_status("error", wifi_status="error", last_error=str(exc))
                except Exception:
                    pass
            return {"status": "error", "error": str(exc)}

    transport = SimulatedTransport() if UNO_SIMULATOR else SerialTransport(UNO_PORT, UNO_BAUDRATE)
    uno = UnoController(transport, UNO_TIMEOUT_SECONDS)
    engine = StockfishEngine(STOCKFISH_PATH, ENGINE_TIME_SECONDS, ENGINE_SKILL_LEVEL)
    game = GameController(engine, uno, SessionStore())
    # BLE camera commands and the local HTTP calibration UI must share one
    # persisted calibration file used by the detector.
    game.calibration_path = Path(LOCAL_STATE_PATH) / "camera_calibration.json"
    detector = PiCameraDetector(
        CAMERA_INDEX, CAMERA_WIDTH, CAMERA_HEIGHT,
        Path(LOCAL_STATE_PATH) / "camera_calibration.json",
        MODEL_PATH, DETECTION_CONFIDENCE,
    )
    start_local_api(LOCAL_API_HOST, LOCAL_API_PORT, game, network, network_config, detector)

    current_network = network.status(
        INTERNET_CHECK_ENABLED,
        INTERNET_CHECK_URL,
        INTERNET_CHECK_TIMEOUT_SECONDS,
    )
    print(f"Network state: {current_network.state} ({current_network.ip_address or 'no IP'})")
    gatt = GattServer(
        DEVICE_ID, on_control=on_control, on_wifi=on_wifi,
        adapter_address=BLE_ADAPTER or None, name=BLE_NAME or None,
        require_bond=BLE_REQUIRE_BOND,
    ) if BLE_ENABLED else None
    if gatt:
        gatt.set_game_handler(game.handle)
        gatt.publish()

    if DEVICE_SECRET:
        try:
            api.connect(DEVICE_ID, DEVICE_SECRET)
            network_config["backend_available"] = True
        except Exception as exc:
            print(f"Backend unavailable; cloud linking is unavailable until this is fixed: {exc}")
    else:
        print("No backend device secret configured; cloud linking is unavailable.")

    onboarding_token = store.load().get("onboarding_token")
    if onboarding_token:
        try:
            claim_pending_token()
        except Exception as exc:
            print(f"Device claim pending: {exc}")

    try:
        api.update_status("online", wifi_status="connected", backend_status="connected")
    except Exception:
        pass

    heartbeat = None
    if DEVICE_SECRET:
        heartbeat = HeartbeatWorker(
            api, DEVICE_ID, HEARTBEAT_SECONDS, DEVICE_SECRET,
            session_snapshot=lambda: game.session.snapshot() if game.session else None,
        )
        heartbeat.start()

    vision = VisionAdapter(game.session, stability_frames=STABLE_LABEL_COUNT)

    print("Pi agent running. Waiting for moves...")
    try:
        while True:
            vision.session = game.session
            if AUTO_DETECT_ENABLED and game.session and game.session.phase.value == "player_turn":
                candidates = detector.detect_candidates(game.session)
                uci, expected_version = vision.observe_candidates(candidates)
                if uci:
                    result = game.handle({"type": "move.propose", "data": {"uci": uci, "expected_version": expected_version}})
                    if result.get("status") == "error":
                        print(f"Automatic move rejected: {result.get('error')}", flush=True)
                time.sleep(DETECT_INTERVAL_SECONDS)
            else:
                time.sleep(0.5)
    except KeyboardInterrupt:
        if heartbeat:
            heartbeat.stop()
        engine.close()
        uno.close()
        if gatt:
            gatt.stop()


if __name__ == "__main__":
    main()
