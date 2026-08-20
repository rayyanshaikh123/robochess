"""Interactive offline terminal game: python -m pi_agent.terminal_game."""

from __future__ import annotations

from pi_agent.config import ENGINE_SKILL_LEVEL, ENGINE_TIME_SECONDS, STOCKFISH_PATH
from pi_agent.engine import StockfishEngine
from pi_agent.game_session import GameSession, SessionError, SessionPhase


def run() -> None:
    session = GameSession()
    session.confirm_setup()
    print("RoboChess offline. You are White. Enter SAN/UCI (e4 or e2e4); reset, quit.")
    with StockfishEngine(STOCKFISH_PATH, ENGINE_TIME_SECONDS, ENGINE_SKILL_LEVEL) as engine:
        while session.phase != SessionPhase.FINISHED:
            print("\n" + str(session.board))
            if session.phase == SessionPhase.PLAYER_TURN:
                text = input("White move> ").strip()
                if text.lower() in {"quit", "exit"}:
                    return
                if text.lower() == "reset":
                    session.reset(); session.confirm_setup(); continue
                try:
                    session.accept_player_move(text, session.version)
                except SessionError as exc:
                    print(exc)
                    continue
            if session.phase == SessionPhase.AWAITING_ENGINE:
                print("Stockfish thinking...")
                session.begin_engine_move()
                uci = engine.best_move(session.board)
                print(f"Black: {session.board.san(session.board.parse_uci(uci))} ({uci})")
                session.accept_engine_move(uci)
    print("\n" + str(session.board))
    print(f"Game finished: {session.board.result()}")


if __name__ == "__main__":
    run()
