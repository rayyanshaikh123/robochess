"""Coordinates BLE/app commands, Stockfish, local state and the Uno."""

from __future__ import annotations

import chess
import json
from pathlib import Path

from pi_agent.engine import StockfishEngine
from pi_agent.game_session import GameSession, SessionError
from pi_agent.uno_controller import UnoController, UnoError, motion_plan
from pi_agent.session_store import SessionStore


class GameController:
    def __init__(self, engine: StockfishEngine, uno: UnoController, store: SessionStore | None = None) -> None:
        self.engine, self.uno = engine, uno
        self.store = store
        self.session: GameSession | None = store.load() if store else None
        self._last_seq = -1
        self._cached_results: dict[int, dict] = {}
        self.calibration_path = Path(__file__).with_name(".state") / "camera_calibration.json"

    def handle(self, message: dict) -> dict:
        data = message.get("data", {})
        sequence = data.get("client_seq")
        if isinstance(sequence, int) and sequence in self._cached_results:
            return self._cached_results[sequence]
        if isinstance(sequence, int) and sequence <= self._last_seq:
            return self._result("error", error="Out-of-order client_seq")
        try:
            result = self._dispatch(message["type"], data)
        except (SessionError, UnoError, RuntimeError, ValueError, KeyError) as exc:
            if self.session and message["type"] == "move.propose":
                self.session.recover(str(exc))
            result = self._result("error", error=str(exc))
        if isinstance(sequence, int):
            self._last_seq = sequence
            self._cached_results[sequence] = result
        if self.store:
            self.store.save(self.session)
        return result

    def _dispatch(self, kind: str, data: dict) -> dict:
        if kind == "camera.status":
            return self._result("camera_status", calibration=self._load_calibration())
        if kind == "camera.calibrate":
            calibration = {"camera_index": int(data.get("camera_index", 0)), "rotation": int(data.get("rotation", 0)), "board_orientation": str(data.get("board_orientation", "white_bottom"))}
            self.calibration_path.parent.mkdir(parents=True, exist_ok=True)
            self.calibration_path.write_text(json.dumps(calibration))
            print(f"Camera calibration saved: {calibration}", flush=True)
            return self._result("camera_calibrated", calibration=calibration)
        if kind == "session.start":
            fen = data.get("initial_fen", chess.STARTING_FEN)
            color = chess.WHITE if data.get("human_color", "white") == "white" else chess.BLACK
            self.session = GameSession(initial_fen=fen, human_color=color)
            self.session.confirm_setup()
            return self._result("state")
        if kind == "gantry.home":
            self.uno.home()
            return self._result("gantry_homed")
        if kind == "gantry.status":
            return self._result("gantry_status", gantry=self.uno.status())
        if not self.session:
            raise SessionError("Start a session first")
        if kind == "session.reset":
            self.session.reset(data.get("initial_fen", chess.STARTING_FEN)); self.session.confirm_setup()
            return self._result("state")
        if kind == "session.undo":
            self.session.undo_last_turn()
            return self._result("state")
        if kind == "session.resume":
            self.session.confirm_setup()
            return self._result("state")
        if kind == "state.request":
            return self._result("state")
        if kind == "move.propose":
            self.session.accept_player_move(data["uci"], data.get("expected_version"))
            state_before_engine = self._result("player_move_accepted")
            self._run_engine_turn()
            state_before_engine["engine_state"] = self.session.snapshot()
            return state_before_engine
        raise ValueError("Unsupported game message")

    def _load_calibration(self) -> dict:
        try:
            return json.loads(self.calibration_path.read_text())
        except (OSError, ValueError):
            return {}

    def _run_engine_turn(self) -> None:
        assert self.session
        if self.session.phase.value == "finished":
            return
        # The app sends move intent only. The Pi verifies the physical safety
        # boundary before converting the engine move into gantry commands.
        self.uno.ensure_homed()
        self.session.begin_engine_move()
        uci = self.engine.best_move(self.session.board)
        move = self.session.parse_legal_move(uci)
        self.uno.execute(motion_plan(self.session.board, move))
        self.session.accept_engine_move(uci)

    def _result(self, status: str, error: str | None = None, **extra: object) -> dict:
        payload = {"status": status, "state": self.session.snapshot() if self.session else None}
        if error:
            payload["error"] = error
        payload.update(extra)
        return payload
