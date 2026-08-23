from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import AsyncMock, patch

from pymongo.errors import DuplicateKeyError

from backend.services.challenge_service import accept, cancel, create, reject

ALICE = "alice"
BOB = "bob"
SERVICE = "backend.services.challenge_service"


def challenge_row(status="pending", expires_in_minutes=10, row_id="c1"):
    return {
        "_id": row_id,
        "challenger_id": ALICE,
        "challenged_id": BOB,
        "status": status,
        "time_control": None,
        "challenger_surface": "app",
        "color_preference": "random",
        "game_id": None,
        "created_at": datetime.now(timezone.utc),
        "expires_at": datetime.now(timezone.utc) + timedelta(minutes=expires_in_minutes),
    }


def profiles(*ids):
    return {i: {"_id": i, "display_name": i.title(), "rating": 1200} for i in ids}


class CreateChallengeTests(unittest.IsolatedAsyncioTestCase):
    async def test_cannot_challenge_yourself(self):
        data, err = await create(None, ALICE, ALICE)
        self.assertIsNone(data)
        self.assertEqual(err, "You cannot challenge yourself")

    async def test_cannot_challenge_a_non_friend(self):
        with patch(f"{SERVICE}.are_friends", AsyncMock(return_value=False)):
            data, err = await create(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "You can only challenge friends")

    async def test_unknown_time_control_is_rejected(self):
        data, err = await create(None, ALICE, BOB, time_control_key="blitz_99_9")
        self.assertIsNone(data)
        self.assertEqual(err, "Unknown time control 'blitz_99_9'")

    async def test_invalid_colour_is_rejected(self):
        data, err = await create(None, ALICE, BOB, color_preference="purple")
        self.assertIsNone(data)
        self.assertEqual(err, "Invalid colour preference")

    async def test_creates_a_pending_challenge(self):
        row = challenge_row()
        with patch(f"{SERVICE}.are_friends", AsyncMock(return_value=True)), \
             patch(f"{SERVICE}.expire_stale", AsyncMock(return_value=0)), \
             patch(f"{SERVICE}.get_pending_between", AsyncMock(return_value=None)), \
             patch(f"{SERVICE}.create_challenge", AsyncMock(return_value=row)), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(BOB))):
            data, err = await create(None, ALICE, BOB, time_control_key="blitz_5_0")
        self.assertIsNone(err)
        self.assertEqual(data["status"], "pending")
        self.assertTrue(data["outgoing"])

    async def test_second_rapid_challenge_is_rejected(self):
        with patch(f"{SERVICE}.are_friends", AsyncMock(return_value=True)), \
             patch(f"{SERVICE}.expire_stale", AsyncMock(return_value=0)), \
             patch(f"{SERVICE}.get_pending_between", AsyncMock(return_value=challenge_row())):
            data, err = await create(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "You already have a pending challenge with this player")

    async def test_unique_index_race_is_reported_cleanly(self):
        with patch(f"{SERVICE}.are_friends", AsyncMock(return_value=True)), \
             patch(f"{SERVICE}.expire_stale", AsyncMock(return_value=0)), \
             patch(f"{SERVICE}.get_pending_between", AsyncMock(return_value=None)), \
             patch(f"{SERVICE}.create_challenge", AsyncMock(side_effect=DuplicateKeyError("dup"))):
            data, err = await create(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "You already have a pending challenge with this player")


class AcceptChallengeTests(unittest.IsolatedAsyncioTestCase):
    async def test_only_the_challenged_player_may_accept(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row())):
            data, err = await accept(None, ALICE, "c1")
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_expired_challenge_cannot_be_accepted(self):
        expired = challenge_row(expires_in_minutes=-1)
        set_status = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=expired)), \
             patch(f"{SERVICE}.set_status", set_status):
            data, err = await accept(None, BOB, "c1")
        self.assertIsNone(data)
        self.assertEqual(err, "Challenge has expired")

    async def test_accept_creates_exactly_one_game(self):
        game = {"_id": "g1", "user_players": [ALICE, BOB],
                "colors": {ALICE: "white", BOB: "black"}, "current_fen": "fen",
                "status": "active", "surfaces": {ALICE: "app", BOB: "app"}}
        create_game = AsyncMock(return_value=game)
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row())), \
             patch(f"{SERVICE}.set_status", AsyncMock(return_value=True)), \
             patch(f"{SERVICE}.create_game_for_players", create_game), \
             patch(f"{SERVICE}.attach_game", AsyncMock(return_value=True)), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(ALICE, BOB))):
            data, err = await accept(None, BOB, "c1")
        self.assertIsNone(err)
        self.assertEqual(data["game_id"], "g1")
        create_game.assert_awaited_once()

    async def test_losing_the_status_race_creates_no_game(self):
        # The compare-and-set fails for the second accept, so no second game.
        create_game = AsyncMock()
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row())), \
             patch(f"{SERVICE}.set_status", AsyncMock(return_value=False)), \
             patch(f"{SERVICE}.create_game_for_players", create_game):
            data, err = await accept(None, BOB, "c1")
        self.assertIsNone(data)
        self.assertEqual(err, "Challenge is no longer pending")
        create_game.assert_not_awaited()

    async def test_already_accepted_challenge_is_refused(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row("accepted"))):
            data, err = await accept(None, BOB, "c1")
        self.assertIsNone(data)
        self.assertEqual(err, "Challenge is no longer pending")


class RejectCancelTests(unittest.IsolatedAsyncioTestCase):
    async def test_challenger_cannot_reject_their_own_challenge(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row())):
            data, err = await reject(None, ALICE, "c1")
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_challenged_player_can_reject(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row())), \
             patch(f"{SERVICE}.set_status", AsyncMock(return_value=True)):
            data, err = await reject(None, BOB, "c1")
        self.assertIsNone(err)
        self.assertEqual(data["status"], "rejected")

    async def test_only_the_challenger_may_cancel(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row())):
            data, err = await cancel(None, BOB, "c1")
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_challenger_can_cancel(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=challenge_row())), \
             patch(f"{SERVICE}.set_status", AsyncMock(return_value=True)):
            data, err = await cancel(None, ALICE, "c1")
        self.assertIsNone(err)
        self.assertEqual(data["status"], "cancelled")

    async def test_missing_challenge(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=None)):
            data, err = await cancel(None, ALICE, "nope")
        self.assertIsNone(data)
        self.assertEqual(err, "Challenge not found")


if __name__ == "__main__":
    unittest.main()
