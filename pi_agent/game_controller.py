"""Coordinates BLE/app commands, Stockfish, local state and the Uno."""

from __future__ import annotations

import chess

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

    def _run_engine_turn(self) -> None:
        assert self.session
        if self.session.phase.value == "finished":
            return
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
