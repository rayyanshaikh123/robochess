import time

from pi_agent.api_client import DeviceApiClient
from pi_agent.gatt_server import GattServer
from pi_agent.network_manager import NetworkManager, NetworkManagerError
from pi_agent.provisioning_store import ProvisioningStore
from pi_agent.config import (
    BLE_ENABLED,
    BLE_ADAPTER,
    BLE_NAME,
    BLE_REQUIRE_BOND,
    DEVICE_ID,
    DEVICE_SECRET,
    HEARTBEAT_SECONDS,
)
from pi_agent.heartbeat import HeartbeatWorker
from pi_agent.vision_adapter import VisionAdapter
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

    def on_control(message: dict) -> dict:
        data = message.get("data") or {}
        token = data.get("onboarding_token")
        if token:
            store.set_onboarding_token(token)
            return {"status": "token_saved"}
        return {"status": "ready"}

    def on_wifi(message: dict) -> dict:
        data = message.get("data") or {}
        try:
            api.update_status("provisioning_wifi", wifi_status="connecting") if api.device_token else None
            result = network.configure(str(data.get("ssid", "")), str(data.get("password", "")))
            if not result.connected:
                raise NetworkManagerError(result.error or "Wi-Fi connection failed")
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
        except Exception as exc:
            # BLE gameplay and the physical board deliberately remain usable offline.
            print(f"Backend unavailable; starting in offline mode: {exc}")
    else:
        print("No backend device secret configured; starting BLE board in local-only mode.")

    onboarding_token = store.load().get("onboarding_token")
    if onboarding_token:
        try:
            api.claim(onboarding_token)
            store.save({})
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

    vision = VisionAdapter(game.session)

    print("Pi agent running. Waiting for moves...")
    try:
        while True:
            # Future OpenCV integration supplies stable candidates through
            # vision.observe_candidates(); polling remains harmless without a camera.
            vision.session = game.session
            uci, expected_version = vision.detect_move()
            if uci:
                game.handle({"type": "move.propose", "data": {"uci": uci, "expected_version": expected_version}})
            time.sleep(0.1)
    except KeyboardInterrupt:
        if heartbeat:
            heartbeat.stop()
        engine.close()
        uno.close()
        if gatt:
            gatt.stop()


if __name__ == "__main__":
    main()
