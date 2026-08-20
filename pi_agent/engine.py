"""Small safe wrapper around a local UCI Stockfish process."""

from __future__ import annotations

import chess
import chess.engine


class StockfishEngine:
    def __init__(self, path: str, think_time: float = 0.5, skill_level: int = 10) -> None:
        self.path, self.think_time, self.skill_level = path, max(0.01, think_time), max(0, min(20, skill_level))
        self._engine: chess.engine.SimpleEngine | None = None

    def __enter__(self) -> "StockfishEngine":
        self.start()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def start(self) -> None:
        if self._engine is None:
            self._engine = chess.engine.SimpleEngine.popen_uci(self.path)
            try:
                self._engine.configure({"Skill Level": self.skill_level})
            except chess.engine.EngineError:
                pass

    def best_move(self, board: chess.Board) -> str:
        self.start()
        assert self._engine is not None
        result = self._engine.play(board, chess.engine.Limit(time=self.think_time))
        if result.move is None:
            raise RuntimeError("Stockfish returned no move")
        return result.move.uci()

    def close(self) -> None:
        if self._engine is not None:
            self._engine.quit()
            self._engine = None
