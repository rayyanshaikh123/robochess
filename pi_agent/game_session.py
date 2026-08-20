"""Local, versioned chess session state owned by the Raspberry Pi."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import hashlib
import uuid

import chess


class SessionPhase(str, Enum):
    IDLE = "idle"
    SETUP_CONFIRMED = "setup_confirmed"
    PLAYER_TURN = "player_turn"
    AWAITING_ENGINE = "awaiting_engine"
    EXECUTING_ENGINE_MOVE = "executing_engine_move"
    RECOVERY = "recovery"
    FINISHED = "finished"


class SessionError(ValueError):
    pass


@dataclass
class GameSession:
    session_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    initial_fen: str = chess.STARTING_FEN
    human_color: chess.Color = chess.WHITE
    board: chess.Board = field(init=False)
    moves: list[str] = field(default_factory=list)
    version: int = 0
    phase: SessionPhase = SessionPhase.IDLE
    last_error: str | None = None

    def __post_init__(self) -> None:
        try:
            self.board = chess.Board(self.initial_fen)
        except ValueError as exc:
            raise SessionError(f"Invalid initial FEN: {exc}") from exc

    def confirm_setup(self) -> None:
        if self.phase not in {SessionPhase.IDLE, SessionPhase.RECOVERY}:
            raise SessionError("Setup can only be confirmed before a game starts or during recovery")
        self.last_error = None
        self.phase = SessionPhase.PLAYER_TURN if self.board.turn == self.human_color else SessionPhase.AWAITING_ENGINE

    def reset(self, initial_fen: str = chess.STARTING_FEN) -> None:
        self.initial_fen = initial_fen
        self.board = chess.Board(initial_fen)
        self.moves.clear()
        self.version = 0
        self.phase = SessionPhase.IDLE
        self.last_error = None

    def _validate_turn(self, actor: str) -> None:
        expected = self.human_color if actor == "player" else not self.human_color
        if self.board.turn != expected:
            raise SessionError(f"It is not the {actor}'s turn")

    def parse_legal_move(self, move_text: str) -> chess.Move:
        value = move_text.strip()
        try:
            move = self.board.parse_uci(value)
        except ValueError:
            try:
                move = self.board.parse_san(value)
            except ValueError as exc:
                raise SessionError(f"Illegal move: {value}") from exc
        if move not in self.board.legal_moves:
            raise SessionError(f"Illegal move: {value}")
        return move

    def accept_player_move(self, move_text: str, expected_version: int | None = None) -> str:
        if self.phase != SessionPhase.PLAYER_TURN:
            raise SessionError(f"Cannot accept a player move while {self.phase.value}")
        self._check_version(expected_version)
        self._validate_turn("player")
        return self._commit(self.parse_legal_move(move_text), SessionPhase.AWAITING_ENGINE)

    def begin_engine_move(self) -> None:
        if self.phase != SessionPhase.AWAITING_ENGINE:
            raise SessionError("Engine is not due to move")
        self._validate_turn("engine")
        self.phase = SessionPhase.EXECUTING_ENGINE_MOVE

    def accept_engine_move(self, move_text: str) -> str:
        if self.phase != SessionPhase.EXECUTING_ENGINE_MOVE:
            raise SessionError("Engine move has not started")
        self._validate_turn("engine")
        return self._commit(self.parse_legal_move(move_text), SessionPhase.PLAYER_TURN)

    def recover(self, reason: str) -> None:
        self.phase = SessionPhase.RECOVERY
        self.last_error = reason

    def _commit(self, move: chess.Move, next_phase: SessionPhase) -> str:
        uci = move.uci()
        self.board.push(move)
        self.moves.append(uci)
        self.version += 1
        self.phase = SessionPhase.FINISHED if self.board.is_game_over() else next_phase
        return uci

    def _check_version(self, expected_version: int | None) -> None:
        if expected_version is not None and expected_version != self.version:
            raise SessionError(f"Stale state: expected version {expected_version}, current version {self.version}")

    def state_hash(self) -> str:
        data = f"{self.initial_fen}|{' '.join(self.moves)}|{self.version}".encode()
        return hashlib.sha256(data).hexdigest()

    def snapshot(self) -> dict:
        return {
            "session_id": self.session_id, "initial_fen": self.initial_fen,
            "fen": self.board.fen(), "moves": self.moves.copy(), "version": self.version,
            "phase": self.phase.value, "turn": "white" if self.board.turn else "black",
            "human_color": "white" if self.human_color else "black",
            "last_error": self.last_error, "state_hash": self.state_hash(),
            "game_over": self.board.is_game_over(), "result": self.board.result() if self.board.is_game_over() else None,
        }

    @classmethod
    def from_snapshot(cls, snapshot: dict) -> "GameSession":
        """Rebuild a session from move history and verify its integrity."""
        color = chess.WHITE if snapshot.get("human_color", "white") == "white" else chess.BLACK
        session = cls(session_id=str(snapshot["session_id"]), initial_fen=str(snapshot.get("initial_fen", chess.STARTING_FEN)), human_color=color)
        for uci in snapshot.get("moves", []):
            move = session.parse_legal_move(str(uci))
            session.board.push(move)
            session.moves.append(move.uci())
        session.version = len(session.moves)
        try:
            session.phase = SessionPhase(snapshot.get("phase", SessionPhase.RECOVERY.value))
        except ValueError:
            session.phase = SessionPhase.RECOVERY
        session.last_error = snapshot.get("last_error")
        if session.phase == SessionPhase.EXECUTING_ENGINE_MOVE:
            session.recover("Pi restarted while a gantry move was in progress; confirm the physical board.")
        if snapshot.get("state_hash") and snapshot["state_hash"] != session.state_hash():
            session.recover("Saved session integrity check failed; reset or reconcile the physical board.")
        return session
