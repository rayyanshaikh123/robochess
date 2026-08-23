from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import AsyncMock, patch

import chess

from backend.services.multiplayer_service import (
    RESULT_BLACK,
    RESULT_DRAW,
    RESULT_WHITE,
    assign_colors,
    derive_play_mode,
    get_game_for_user,
    offer_draw,
    post_chat,
    resign,
    respond_to_draw,
    resolve_time_control,
    serialize_game,
    side_to_move,
    submit_move,
)

ALICE = "alice"
BOB = "bob"
MALLORY = "mallory"
SERVICE = "backend.services.multiplayer_service"

START_FEN = chess.Board().fen()
# Black to move, one move from being mated by Qxf7#.
SCHOLARS_FEN = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4"


def game_row(fen=START_FEN, status="active", row_id="g1", **overrides):
    row = {
        "_id": row_id,
        "user_players": [ALICE, BOB],
        "colors": {ALICE: "white", BOB: "black"},
        "surfaces": {ALICE: "app", BOB: "app"},
        "play_mode": "app_vs_app",
        "current_fen": fen,
        "status": status,
        "game_version": 0,
        "last_move": None,
        "result": None,
        "winner_id": None,
        "end_reason": None,
        "draw_offer_by": None,
        "time_control": None,
        "clocks": None,
        "turn_started_at": None,
        "created_at": None,
        "updated_at": None,
    }
    row.update(overrides)
    return row


class HelperTests(unittest.TestCase):
    def test_side_to_move_reads_the_fen(self):
        self.assertEqual(side_to_move(START_FEN), "white")
        self.assertIsNone(side_to_move("not-a-fen"))

    def test_colour_preference_is_honoured(self):
        self.assertEqual(assign_colors(ALICE, BOB, "white")[ALICE], "white")
        self.assertEqual(assign_colors(ALICE, BOB, "black")[ALICE], "black")

    def test_colours_are_always_opposite(self):
        colors = assign_colors(ALICE, BOB, "random")
        self.assertNotEqual(colors[ALICE], colors[BOB])

    def test_play_mode_covers_all_three_surface_combinations(self):
        self.assertEqual(derive_play_mode("app", "app"), "app_vs_app")
        self.assertEqual(derive_play_mode("app", "board-1"), "app_vs_board")
        self.assertEqual(derive_play_mode("board-1", "board-2"), "board_vs_board")

    def test_unlimited_time_control_resolves_to_none(self):
        value, err = resolve_time_control("unlimited")
        self.assertIsNone(err)
        self.assertIsNone(value)

    def test_known_time_control_carries_its_key(self):
        value, err = resolve_time_control("blitz_3_2")
        self.assertIsNone(err)
        self.assertEqual(value["increment_seconds"], 2)
        self.assertEqual(value["key"], "blitz_3_2")

    def test_serialization_is_from_the_callers_point_of_view(self):
        row = game_row(status="completed", result=RESULT_WHITE, winner_id=ALICE)
        alice_view = serialize_game(row, ALICE)
        bob_view = serialize_game(row, BOB)
        self.assertEqual(alice_view["your_result"], "won")
        self.assertEqual(bob_view["your_result"], "lost")
        self.assertEqual(alice_view["your_color"], "white")
        self.assertEqual(bob_view["opponent"]["user_id"], ALICE)

    def test_draw_is_a_draw_for_both_players(self):
        row = game_row(status="completed", result=RESULT_DRAW)
        self.assertEqual(serialize_game(row, ALICE)["your_result"], "draw")
        self.assertEqual(serialize_game(row, BOB)["your_result"], "draw")


class AuthorizationTests(unittest.IsolatedAsyncioTestCase):
    async def test_non_participant_cannot_read_a_game(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())):
            data, err = await get_game_for_user(None, "g1", MALLORY)
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_non_participant_cannot_move(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())):
            data, err = await submit_move(None, "g1", MALLORY, "e2e4")
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_non_participant_cannot_resign(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())):
            data, err = await resign(None, "g1", MALLORY)
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_non_participant_cannot_chat(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())):
            data, err = await post_chat(None, "g1", MALLORY, "hello")
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_missing_game(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=None)):
            data, err = await submit_move(None, "nope", ALICE, "e2e4")
        self.assertIsNone(data)
        self.assertEqual(err, "Game not found")


class MoveTests(unittest.IsolatedAsyncioTestCase):
    async def test_player_cannot_move_out_of_turn(self):
        # White to move, but Black tries to play.
        validate = AsyncMock()
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())), \
             patch(f"{SERVICE}.validate_and_record_move", validate):
            data, err = await submit_move(None, "g1", BOB, "e7e5")
        self.assertIsNone(data)
        self.assertEqual(err, "It is not your turn")
        validate.assert_not_awaited()

    async def test_illegal_move_is_rejected_by_the_engine(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())), \
             patch(f"{SERVICE}.validate_and_record_move",
                   AsyncMock(return_value=(None, "Illegal move"))), \
             patch(f"{SERVICE}.set_turn_started", AsyncMock()):
            data, err = await submit_move(None, "g1", ALICE, "e2e5")
        self.assertIsNone(data)
        self.assertEqual(err, "Illegal move")

    async def test_cannot_move_in_a_finished_game(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row(status="completed"))):
            data, err = await submit_move(None, "g1", ALICE, "e2e4")
        self.assertIsNone(data)
        self.assertEqual(err, "Game is already finished")

    async def test_legal_move_is_recorded(self):
        after = chess.Board()
        after.push_uci("e2e4")
        state = {"current_fen": after.fen(), "game_version": 1, "status": "active"}
        moved = game_row(fen=after.fen(), game_version=1, last_move="e2e4")
        with patch(f"{SERVICE}.get_game", AsyncMock(side_effect=[game_row(), moved])), \
             patch(f"{SERVICE}.validate_and_record_move", AsyncMock(return_value=(state, None))), \
             patch(f"{SERVICE}.set_turn_started", AsyncMock()), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={})):
            data, err = await submit_move(None, "g1", ALICE, "e2e4")
        self.assertIsNone(err)
        self.assertEqual(data["last_move"], "e2e4")
        self.assertEqual(data["turn"], "black")

    async def test_checkmate_finishes_the_game_for_the_mover(self):
        board = chess.Board(SCHOLARS_FEN)
        board.push_uci("f3f7")  # Qxf7#
        self.assertTrue(board.is_checkmate())
        state = {"current_fen": board.fen(), "game_version": 1, "status": "active"}
        finished = game_row(fen=board.fen(), status="completed",
                            result=RESULT_WHITE, winner_id=ALICE, end_reason="checkmate")
        finish = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_game",
                   AsyncMock(side_effect=[game_row(fen=SCHOLARS_FEN), finished])), \
             patch(f"{SERVICE}.validate_and_record_move", AsyncMock(return_value=(state, None))), \
             patch(f"{SERVICE}.set_turn_started", AsyncMock()), \
             patch(f"{SERVICE}.finish_game", finish), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={})):
            data, err = await submit_move(None, "g1", ALICE, "f3f7")
        self.assertIsNone(err)
        finish.assert_awaited_once()
        self.assertEqual(finish.await_args.args[2], RESULT_WHITE)
        self.assertEqual(finish.await_args.args[3], ALICE)
        self.assertEqual(data["your_result"], "won")

    async def test_running_out_of_time_loses_the_game(self):
        stale = datetime.now(timezone.utc) - timedelta(seconds=120)
        timed = game_row(
            time_control={"initial_seconds": 60, "increment_seconds": 0, "key": "bullet_1_0"},
            clocks={ALICE: {"remaining_ms": 60000}, BOB: {"remaining_ms": 60000}},
            turn_started_at=stale,
        )
        finished = game_row(status="completed", result=RESULT_BLACK,
                            winner_id=BOB, end_reason="timeout")
        finish = AsyncMock(return_value=True)
        validate = AsyncMock()
        with patch(f"{SERVICE}.get_game", AsyncMock(side_effect=[timed, finished])), \
             patch(f"{SERVICE}.update_clocks", AsyncMock(return_value=True)), \
             patch(f"{SERVICE}.finish_game", finish), \
             patch(f"{SERVICE}.validate_and_record_move", validate), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={})):
            data, err = await submit_move(None, "g1", ALICE, "e2e4")
        self.assertIsNone(err)
        # The move never reaches the engine: the flag fell first.
        validate.assert_not_awaited()
        self.assertEqual(finish.await_args.args[3], BOB)
        self.assertEqual(data["your_result"], "lost")


class EndGameTests(unittest.IsolatedAsyncioTestCase):
    async def test_resign_hands_the_win_to_the_opponent(self):
        finished = game_row(status="completed", result=RESULT_BLACK,
                            winner_id=BOB, end_reason="resignation")
        finish = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_game", AsyncMock(side_effect=[game_row(), finished])), \
             patch(f"{SERVICE}.finish_game", finish), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={})):
            data, err = await resign(None, "g1", ALICE)
        self.assertIsNone(err)
        self.assertEqual(finish.await_args.args[2], RESULT_BLACK)
        self.assertEqual(finish.await_args.args[3], BOB)
        self.assertEqual(data["your_result"], "lost")

    async def test_cannot_resign_twice(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row(status="completed"))):
            data, err = await resign(None, "g1", ALICE)
        self.assertIsNone(data)
        self.assertEqual(err, "Game is already finished")

    async def test_draw_offer_is_recorded(self):
        offered = game_row(draw_offer_by=ALICE)
        with patch(f"{SERVICE}.get_game", AsyncMock(side_effect=[game_row(), offered])), \
             patch(f"{SERVICE}.set_draw_offer", AsyncMock(return_value=True)):
            data, err = await offer_draw(None, "g1", ALICE)
        self.assertIsNone(err)
        self.assertEqual(data["draw_offer_by"], ALICE)

    async def test_cannot_answer_your_own_draw_offer(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row(draw_offer_by=ALICE))):
            data, err = await respond_to_draw(None, "g1", ALICE, accept=True)
        self.assertIsNone(data)
        self.assertEqual(err, "You cannot answer your own draw offer")

    async def test_accepting_a_draw_finishes_the_game(self):
        drawn = game_row(status="completed", result=RESULT_DRAW, end_reason="draw_agreed")
        finish = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_game",
                   AsyncMock(side_effect=[game_row(draw_offer_by=ALICE), drawn])), \
             patch(f"{SERVICE}.finish_game", finish), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={})):
            data, err = await respond_to_draw(None, "g1", BOB, accept=True)
        self.assertIsNone(err)
        self.assertEqual(finish.await_args.args[2], RESULT_DRAW)
        self.assertEqual(data["your_result"], "draw")

    async def test_declining_a_draw_clears_the_offer_and_continues(self):
        cleared = game_row(draw_offer_by=None)
        set_offer = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_game",
                   AsyncMock(side_effect=[game_row(draw_offer_by=ALICE), cleared])), \
             patch(f"{SERVICE}.set_draw_offer", set_offer), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={})):
            data, err = await respond_to_draw(None, "g1", BOB, accept=False)
        self.assertIsNone(err)
        self.assertEqual(data["status"], "active")
        set_offer.assert_awaited_once_with(None, "g1", None)

    async def test_answering_a_draw_that_was_never_offered(self):
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())):
            data, err = await respond_to_draw(None, "g1", BOB, accept=True)
        self.assertIsNone(data)
        self.assertEqual(err, "No draw has been offered")


class ChatTests(unittest.IsolatedAsyncioTestCase):
    async def test_empty_message_is_rejected(self):
        data, err = await post_chat(None, "g1", ALICE, "   ")
        self.assertIsNone(data)
        self.assertEqual(err, "Message cannot be empty")

    async def test_overlong_message_is_rejected(self):
        data, err = await post_chat(None, "g1", ALICE, "x" * 501)
        self.assertIsNone(data)
        self.assertEqual(err, "Message is too long")

    async def test_participant_can_chat(self):
        row = {"_id": "m1", "created_at": None}
        with patch(f"{SERVICE}.get_game", AsyncMock(return_value=game_row())), \
             patch(f"{SERVICE}.add_chat", AsyncMock(return_value=row)):
            data, err = await post_chat(None, "g1", ALICE, "good luck")
        self.assertIsNone(err)
        self.assertEqual(data["text"], "good luck")


if __name__ == "__main__":
    unittest.main()
