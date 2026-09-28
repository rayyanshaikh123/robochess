"""Regression tests for the Pi agent review fixes."""

import json
import time
import unittest

import chess

from pi_agent.ble_protocol import envelope
from pi_agent.game_controller import GameController
from pi_agent.game_session import GameSession, SessionPhase
from pi_agent.gatt_server import GattServer


class InstantEngine:
    def __init__(self, reply="e2e4"):
        self.reply = reply
        self.calls = 0

    def best_move(self, board):
        self.calls += 1
        return self.reply


class HomedUno:
    def ensure_homed(self):
        return {"homed": True}

    def execute(self, plan):
        return None


def wait_for(predicate, timeout=2.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return False


class EngineTurnTests(unittest.TestCase):
    def test_engine_opens_when_human_plays_black(self):
        engine = InstantEngine("e2e4")
        controller = GameController(engine, HomedUno())
        controller.handle({"type": "session.start", "data": {"human_color": "black"}})
        self.assertTrue(wait_for(lambda: controller.session.phase == SessionPhase.PLAYER_TURN))
        self.assertEqual(controller.session.moves, ["e2e4"])

    def test_human_white_start_does_not_run_engine(self):
        engine = InstantEngine()
        controller = GameController(engine, HomedUno())
        controller.handle({"type": "session.start", "data": {"human_color": "white"}})
        time.sleep(0.1)
        self.assertEqual(engine.calls, 0)
        self.assertEqual(controller.session.phase, SessionPhase.PLAYER_TURN)


class DuplicateCommandTests(unittest.TestCase):
    def test_retransmitted_request_is_applied_once(self):
        controller = GameController(InstantEngine("e7e5"), HomedUno())
        controller.handle({"type": "session.start", "data": {}})
        move = {"type": "move.propose", "request_id": "r-1",
                "data": {"uci": "e2e4", "expected_version": 0}}
        first = controller.handle(move)
        second = controller.handle(move)
        self.assertEqual(first, second)
        self.assertTrue(wait_for(lambda: controller.session.version == 2))

    def test_app_relaunch_with_reset_client_seq_is_not_rejected(self):
        controller = GameController(InstantEngine(), HomedUno())
        controller.handle({"type": "session.start", "request_id": "a-1", "data": {"client_seq": 5}})
        # A relaunched app starts counting from 1 again, with a new request_id.
        result = controller.handle({"type": "state.request", "request_id": "b-1", "data": {"client_seq": 1}})
        self.assertEqual(result["status"], "state")

    def test_result_cache_is_bounded(self):
        controller = GameController(InstantEngine(), HomedUno())
        for index in range(200):
            controller.handle({"type": "camera.status", "request_id": f"r-{index}", "data": {}})
        self.assertLessEqual(len(controller._cached_results), 64)


class UndoTests(unittest.TestCase):
    def test_undo_after_human_mate_rewinds_one_ply(self):
        # Fool's mate with the human as black: black's mate ends the game.
        session = GameSession(human_color=chess.BLACK)
        for uci in ("f2f3", "e7e5", "g2g4"):
            session.board.push_uci(uci)
            session.moves.append(uci)
        session.version = 3
        session.phase = SessionPhase.PLAYER_TURN
        session.accept_player_move("d8h4", 3)
        self.assertEqual(session.phase, SessionPhase.FINISHED)
        session.undo_last_turn()
        self.assertEqual(session.moves, ["f2f3", "e7e5", "g2g4"])
        self.assertEqual(session.board.turn, chess.BLACK)


class BleReassemblyTests(unittest.TestCase):
    def setUp(self):
        self.gatt = GattServer("board-001", on_wifi=lambda message: {"status": "ok", "ssid": message["data"]["ssid"]})

    def test_message_split_over_writes_is_reassembled(self):
        raw = json.dumps(envelope("wifi.provision", "board-001", ssid="Home", password="x" * 300)).encode()
        replies = []
        for offset in range(0, len(raw), 180):
            replies = self.gatt.handle_wifi(raw[offset:offset + 180])
        self.assertTrue(replies)
        self.assertIn(b"Home", b"".join(replies))

    def test_new_message_recovers_from_abandoned_partial(self):
        partial = json.dumps(envelope("wifi.provision", "board-001", ssid="Lost", password="p" * 300)).encode()[:120]
        self.assertEqual(self.gatt.handle_wifi(partial), [])
        full = json.dumps(envelope("wifi.provision", "board-001", ssid="Home", password="pw")).encode()
        replies = self.gatt.handle_wifi(full)
        self.assertTrue(replies, "a complete message must parse after a lost partial")

    def test_queued_writes_are_processed_in_order(self):
        seen = []
        self.gatt._handle_wifi_in_bg = lambda raw: seen.append(self.gatt.handle_wifi(raw))
        self.gatt._start_workers()
        raw = json.dumps(envelope("wifi.provision", "board-001", ssid="Home", password="x" * 500)).encode()
        for offset in range(0, len(raw), 100):
            self.gatt._on_wifi_write(list(raw[offset:offset + 100]), {})
        self.assertTrue(wait_for(lambda: any(seen)))


class LocalApiTests(unittest.TestCase):
    def setUp(self):
        from fastapi.testclient import TestClient

        from pi_agent.local_api import LocalApiHost
        from pi_agent.network_manager import NetworkStatus

        class FakeNetwork:
            calls = 0

            def status(self, *args):
                FakeNetwork.calls += 1
                return NetworkStatus(True, ssid="Home", ip_address="192.168.0.219", state="internet_available")

        class FakeDetector:
            model_path = ""
            confidence = 0.1
            calibrated = False
            model_available = True
            session_getter = None
            pending_auto_move = None
            pending_auto_san = None
            loads = 0

            def load_model(self):
                FakeDetector.loads += 1

            def status(self):
                return {"ready": True, "model_available": True, "camera": {"opened": True}}

            def start_hand_monitoring(self, session):
                return None

        self.network_cls, self.detector_cls = FakeNetwork, FakeDetector
        self.controller = GameController(InstantEngine("e2e4"), HomedUno())
        self.controller.uno.status = lambda: {"homed": True}
        config = {
            "state_path": "/tmp/robochess-review-test", "camera_index": 0, "width": 800,
            "height": 600, "jpeg_quality": 80, "internet_check_enabled": False,
            "internet_check_url": "", "internet_check_timeout": 1,
        }
        self.api = LocalApiHost(self.controller, FakeNetwork(), config, FakeDetector())
        self.client = TestClient(self.api.app)

    def test_model_load_no_longer_crashes(self):
        response = self.client.post("/local/model/load", json={"vision_mode": "cloud"})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.detector_cls.loads, 1)

    def test_game_start_honours_black(self):
        response = self.client.post("/local/game/start", json={"human_color": "black"})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.controller.session.human_color, chess.BLACK)
        self.assertTrue(wait_for(lambda: self.controller.session.moves == ["e2e4"]))

    def test_game_start_without_body_defaults_to_white(self):
        response = self.client.post("/local/game/start")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.controller.session.human_color, chess.WHITE)

    def test_network_status_is_cached_between_polls(self):
        for _ in range(5):
            self.client.get("/local/network/status")
        self.assertEqual(self.network_cls.calls, 1)


if __name__ == "__main__":
    unittest.main()
