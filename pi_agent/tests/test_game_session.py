import unittest
from tempfile import TemporaryDirectory

import chess

from pi_agent.game_session import GameSession, SessionError, SessionPhase
from pi_agent.uno_controller import SimulatedTransport, UnoController, UnoError, motion_plan
from pi_agent.session_store import SessionStore
from pi_agent.ble_protocol import decode_chunk, encode_chunks


class GameSessionTests(unittest.TestCase):
    def setUp(self):
        self.session = GameSession()
        self.session.confirm_setup()

    def test_player_move_advances_version(self):
        self.assertEqual(self.session.accept_player_move("e4", 0), "e2e4")
        self.assertEqual(self.session.version, 1)
        self.assertEqual(self.session.phase, SessionPhase.AWAITING_ENGINE)

    def test_stale_and_illegal_moves_are_rejected(self):
        with self.assertRaises(SessionError):
            self.session.accept_player_move("e5", 0)
        with self.assertRaises(SessionError):
            self.session.accept_player_move("e4", 1)

    def test_reset_returns_to_standard_setup(self):
        self.session.accept_player_move("e2e4")
        self.session.reset()
        self.assertEqual(self.session.board.fen(), chess.STARTING_FEN)
        self.assertEqual(self.session.version, 0)
        self.assertEqual(self.session.phase, SessionPhase.IDLE)

    def test_session_round_trip_and_interrupted_gantry_recovery(self):
        self.session.accept_player_move("e2e4")
        self.session.begin_engine_move()
        with TemporaryDirectory() as directory:
            store = SessionStore(f"{directory}/session.json")
            store.save(self.session)
            restored = store.load()
        self.assertIsNotNone(restored)
        assert restored is not None
        self.assertEqual(restored.moves, ["e2e4"])
        self.assertEqual(restored.phase, SessionPhase.RECOVERY)


class UnoPlanTests(unittest.TestCase):
    def test_castling_and_en_passant_plans(self):
        board = chess.Board("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        plan = motion_plan(board, chess.Move.from_uci("e1g1"))
        self.assertEqual([operation["op"] for operation in plan.operations], ["move", "move"])
        board = chess.Board("8/8/8/3pP3/8/8/8/4K2k w - d6 0 1")
        plan = motion_plan(board, chess.Move.from_uci("e5d6"))
        self.assertEqual(plan.operations[0], {"op": "remove", "square": "d5"})

    def test_simulator_acknowledges_and_failure_raises(self):
        plan = type("P", (), {"uci": "e2e4", "operations": []})()
        UnoController(SimulatedTransport()).execute(plan)
        with self.assertRaises(UnoError):
            UnoController(SimulatedTransport(fail=True), retries=0).execute(plan)


class BleProtocolTests(unittest.TestCase):
    def test_long_state_is_framed_and_reassembles(self):
        message = {"version": "1", "request_id": "request", "device_id": "board", "data": {"fen": "x" * 400}}
        chunks = encode_chunks(message)
        self.assertGreater(len(chunks), 1)
        decoded = [decode_chunk(chunk) for chunk in chunks]
        self.assertTrue(all(value is not None for value in decoded))
        payload = b"".join(value[3] for value in sorted(decoded, key=lambda value: value[1]))
        self.assertEqual(payload, __import__("json").dumps(message, separators=(",", ":")).encode())


if __name__ == "__main__":
    unittest.main()
