import unittest
from unittest.mock import AsyncMock, patch

from backend.services.board_session_service import _validated_fen, sync_board_session


class BoardSessionValidationTests(unittest.TestCase):
    def test_replays_legal_history(self):
        fen = _validated_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", ["e2e4", "e7e5"])
        self.assertIn(" w ", fen)

    def test_rejects_illegal_history(self):
        with self.assertRaises(ValueError):
            _validated_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", ["e2e5"])


class BoardSessionSyncTests(unittest.IsolatedAsyncioTestCase):
    payload = {"session_id": "s1", "initial_fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "moves": ["e2e4"], "version": 1, "state_hash": "a" * 64}

    async def test_existing_hash_is_idempotent(self):
        existing = {"state_hash": "a" * 64, "moves": ["e2e4"], "version": 1}
        with patch("backend.services.board_session_service.get_session", AsyncMock(return_value=existing)):
            result, error = await sync_board_session(None, "pi", self.payload)
        self.assertIsNone(error)
        self.assertEqual(result["sync_status"], "unchanged")

    async def test_divergence_creates_conflict_without_replace(self):
        existing = {"state_hash": "b" * 64, "moves": ["d2d4"], "version": 1}
        conflict = AsyncMock()
        with patch("backend.services.board_session_service.get_session", AsyncMock(return_value=existing)), patch("backend.services.board_session_service.create_conflict", conflict), patch("backend.services.board_session_service.replace_session", AsyncMock()) as replace:
            result, error = await sync_board_session(None, "pi", self.payload)
        self.assertIsNone(error)
        self.assertEqual(result["sync_status"], "conflict")
        conflict.assert_awaited_once()
        replace.assert_not_awaited()

    async def test_longer_matching_history_replaces_session(self):
        payload = {**self.payload, "moves": ["e2e4", "e7e5"], "version": 2, "state_hash": "c" * 64}
        existing = {"state_hash": "a" * 64, "moves": ["e2e4"], "version": 1}
        replace = AsyncMock()
        with patch("backend.services.board_session_service.get_session", AsyncMock(return_value=existing)), patch("backend.services.board_session_service.replace_session", replace):
            result, error = await sync_board_session(None, "pi", payload)
        self.assertIsNone(error)
        self.assertEqual(result["sync_status"], "updated")
        replace.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
