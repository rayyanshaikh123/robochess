import threading
import time
import unittest

import chess

from pi_agent.game_controller import GameController
from pi_agent.game_session import SessionPhase


class BlockingEngine:
    def __init__(self):
        self.started = threading.Event()
        self.release = threading.Event()

    def best_move(self, board):
        self.started.set()
        self.release.wait(timeout=2)
        return "e7e5"


class FakeUno:
    def __init__(self):
        self.started = threading.Event()
        self.release = threading.Event()

    def ensure_homed(self):
        return {"homed": True}

    def execute(self, plan):
        self.started.set()
        self.release.wait(timeout=2)


class GameControllerTests(unittest.TestCase):
    def test_player_move_returns_before_engine_and_gantry_finish(self):
        engine = BlockingEngine()
        uno = FakeUno()
        controller = GameController(engine, uno)
        controller.handle({"type": "session.start", "data": {}})

        result = controller.handle({
            "type": "move.propose",
            "data": {"uci": "e2e4", "expected_version": 0},
        })

        self.assertEqual(result["status"], "player_move_accepted")
        self.assertTrue(result["engine_pending"])
        self.assertEqual(result["state"]["phase"], SessionPhase.AWAITING_ENGINE.value)
        self.assertTrue(engine.started.wait(timeout=1))

        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            state = controller.handle({"type": "state.request", "data": {}})["state"]
            if state["phase"] == SessionPhase.EXECUTING_ENGINE_MOVE.value:
                break
            time.sleep(0.01)
        else:
            self.fail("engine phase was not persisted while the worker was running")

        self.assertEqual(controller.session.moves, ["e2e4"])
        engine.release.set()
        uno.release.set()
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and controller.session.phase != SessionPhase.PLAYER_TURN:
            time.sleep(0.01)
        self.assertEqual(controller.session.moves, ["e2e4", "e7e5"])
        self.assertEqual(controller.session.phase, SessionPhase.PLAYER_TURN)

    def test_duplicate_move_is_rejected_while_engine_is_pending(self):
        engine = BlockingEngine()
        uno = FakeUno()
        controller = GameController(engine, uno)
        controller.handle({"type": "session.start", "data": {}})
        controller.handle({"type": "move.propose", "data": {"uci": "e2e4"}})
        self.assertEqual(
            controller.handle({"type": "move.propose", "data": {"uci": "d2d4"}})["status"],
            "error",
        )
        engine.release.set()
        uno.release.set()


if __name__ == "__main__":
    unittest.main()
