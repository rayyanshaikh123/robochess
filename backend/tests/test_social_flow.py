"""End-to-end integration across the friendship, challenge and game services.

These exercise the real service code composed together -- only the repository
layer is swapped for an in-memory store that mimics the MongoDB semantics the
services depend on (unique friendship pairs, status compare-and-set, and the
optimistic-concurrency version guard on moves).

The scenarios follow the product's stated edge cases: request/accept/reject/
cancel, challenge lifecycle, exactly-once game creation, turn enforcement,
illegal moves, resignation and access control.
"""

from contextlib import ExitStack
from datetime import datetime, timezone
import unittest
from unittest.mock import patch

import chess

from backend.repositories.friendship_repo import pair_key
from backend.services import challenge_service, friendship_service, multiplayer_service

ALICE = "alice"
BOB = "bob"
MALLORY = "mallory"


class Store:
    """Minimal stand-in for the collections these services touch."""

    def __init__(self):
        self.friendships: dict[str, dict] = {}
        self.challenges: dict[str, dict] = {}
        self.games: dict[str, dict] = {}
        self.moves: set[tuple[str, int]] = set()
        self.chats: list[dict] = []
        self.users = {
            ALICE: {"_id": ALICE, "display_name": "Alice", "rating": 1200,
                    "email": "alice@example.com", "password_hash": "x"},
            BOB: {"_id": BOB, "display_name": "Bob", "rating": 1250,
                  "email": "bob@example.com", "password_hash": "x"},
            MALLORY: {"_id": MALLORY, "display_name": "Mallory", "rating": 900,
                      "email": "m@example.com", "password_hash": "x"},
        }
        self._seq = 0

    def _next_id(self, prefix: str) -> str:
        self._seq += 1
        return f"{prefix}{self._seq}"

    # -- users ---------------------------------------------------------------

    async def get_many_by_ids(self, _db, user_ids):
        return {u: self.users[u] for u in user_ids if u in self.users}

    # -- friendships ---------------------------------------------------------

    async def get_between(self, _db, a, b):
        user_a, user_b = pair_key(a, b)
        return self.friendships.get(f"{user_a}|{user_b}")

    async def friendship_by_id(self, _db, fid):
        return next((f for f in self.friendships.values() if f["_id"] == fid), None)

    async def create_friendship(self, _db, requester, addressee, status="pending"):
        user_a, user_b = pair_key(requester, addressee)
        key = f"{user_a}|{user_b}"
        if key in self.friendships:
            from pymongo.errors import DuplicateKeyError

            raise DuplicateKeyError("duplicate friendship")
        row = {
            "_id": self._next_id("f"),
            "user_a": user_a,
            "user_b": user_b,
            "requester_id": requester,
            "addressee_id": addressee,
            "status": status,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        }
        self.friendships[key] = row
        return row

    async def set_friendship_status(self, _db, fid, status, expected_status=None):
        row = await self.friendship_by_id(None, fid)
        if row is None:
            return False
        if expected_status is not None and row["status"] != expected_status:
            return False
        row["status"] = status
        return True

    async def reopen_request(self, _db, fid, requester, addressee):
        row = await self.friendship_by_id(None, fid)
        if row is None or row["status"] != "rejected":
            return False
        row.update({"status": "pending", "requester_id": requester,
                    "addressee_id": addressee})
        return True

    async def delete_friendship(self, _db, fid):
        for key, row in list(self.friendships.items()):
            if row["_id"] == fid:
                del self.friendships[key]
                return True
        return False

    async def list_by_status(self, _db, user_id, status):
        return [f for f in self.friendships.values()
                if f["status"] == status and user_id in (f["user_a"], f["user_b"])]

    async def list_requests(self, _db, user_id, incoming):
        field = "addressee_id" if incoming else "requester_id"
        return [f for f in self.friendships.values()
                if f["status"] == "pending" and f.get(field) == user_id]

    async def are_friends(self, _db, a, b):
        row = await self.get_between(None, a, b)
        return bool(row and row["status"] == "accepted")

    # -- challenges ----------------------------------------------------------

    async def create_challenge(self, _db, challenger_id, challenged_id, time_control,
                               play_mode, challenger_surface, color_preference,
                               expires_at):
        for row in self.challenges.values():
            if (row["challenger_id"] == challenger_id
                    and row["challenged_id"] == challenged_id
                    and row["status"] == "pending"):
                from pymongo.errors import DuplicateKeyError

                raise DuplicateKeyError("duplicate pending challenge")
        row = {
            "_id": self._next_id("c"),
            "challenger_id": challenger_id,
            "challenged_id": challenged_id,
            "status": "pending",
            "time_control": time_control,
            "challenger_surface": challenger_surface,
            "color_preference": color_preference,
            "game_id": None,
            "created_at": datetime.now(timezone.utc),
            "expires_at": expires_at,
        }
        self.challenges[row["_id"]] = row
        return row

    async def challenge_by_id(self, _db, cid):
        return self.challenges.get(cid)

    async def get_pending_between(self, _db, challenger_id, challenged_id):
        return next(
            (r for r in self.challenges.values()
             if r["challenger_id"] == challenger_id
             and r["challenged_id"] == challenged_id
             and r["status"] == "pending"),
            None,
        )

    async def set_challenge_status(self, _db, cid, status, expected_status="pending"):
        row = self.challenges.get(cid)
        if row is None or row["status"] != expected_status:
            return False
        row["status"] = status
        return True

    async def attach_game(self, _db, cid, game_id, challenged_surface):
        row = self.challenges.get(cid)
        if row is None:
            return False
        row.update({"game_id": game_id, "challenged_surface": challenged_surface})
        return True

    async def list_challenges(self, _db, user_id, incoming, status=None):
        field = "challenged_id" if incoming else "challenger_id"
        return [r for r in self.challenges.values()
                if r[field] == user_id and (status is None or r["status"] == status)]

    async def expire_stale(self, _db, now=None):
        moment = now or datetime.now(timezone.utc)
        count = 0
        for row in self.challenges.values():
            deadline = row.get("expires_at")
            if row["status"] == "pending" and deadline and deadline <= moment:
                row["status"] = "expired"
                count += 1
        return count

    # -- games ---------------------------------------------------------------

    async def create_multiplayer_game(self, _db, user_players, colors, surfaces,
                                      play_mode, current_fen, time_control=None,
                                      clocks=None, rematch_of=None):
        row = {
            "_id": self._next_id("g"),
            "players": [],
            "user_players": user_players,
            "colors": colors,
            "surfaces": surfaces,
            "play_mode": play_mode,
            "current_fen": current_fen,
            "status": "active",
            "game_version": 0,
            "last_move": None,
            "result": None,
            "winner_id": None,
            "end_reason": None,
            "draw_offer_by": None,
            "time_control": time_control,
            "clocks": clocks,
            "rematch_of": rematch_of,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        }
        self.games[row["_id"]] = row
        return row

    async def get_game(self, _db, game_id, session=None):
        return self.games.get(game_id)

    async def list_games(self, _db, user_id, statuses=None):
        return [g for g in self.games.values()
                if user_id in g["user_players"]
                and (statuses is None or g["status"] in statuses)]

    async def finish_game(self, _db, game_id, result, winner_id, end_reason):
        game = self.games.get(game_id)
        if game is None or game["status"] != "active":
            return False
        game.update({"status": "completed", "result": result,
                     "winner_id": winner_id, "end_reason": end_reason,
                     "draw_offer_by": None})
        return True

    async def set_draw_offer(self, _db, game_id, user_id):
        game = self.games.get(game_id)
        if game is None or game["status"] != "active":
            return False
        game["draw_offer_by"] = user_id
        return True

    async def set_turn_started(self, _db, game_id, moment):
        game = self.games.get(game_id)
        if game is None:
            return False
        game["turn_started_at"] = moment
        return True

    async def update_clocks(self, _db, game_id, clocks):
        game = self.games.get(game_id)
        if game is None:
            return False
        game["clocks"] = clocks
        return True

    async def add_chat(self, _db, game_id, user_id, text):
        row = {"_id": self._next_id("m"), "game_id": game_id, "user_id": user_id,
               "text": text, "created_at": datetime.now(timezone.utc)}
        self.chats.append(row)
        return row

    async def list_chat(self, _db, game_id):
        return [c for c in self.chats if c["game_id"] == game_id]

    # -- move recording (game_service's repo layer) --------------------------

    async def update_game_state(self, _db, game_id, expected_version, current_fen,
                                last_move, session=None):
        game = self.games.get(game_id)
        if game is None or game["game_version"] != expected_version:
            return False  # the OCC guard
        game.update({"current_fen": current_fen, "last_move": last_move,
                     "game_version": expected_version + 1})
        return True

    async def insert_move(self, _db, game_id, move_number, uci, fen_after):
        key = (game_id, move_number)
        if key in self.moves:
            from pymongo.errors import DuplicateKeyError

            raise DuplicateKeyError("duplicate move")
        self.moves.add(key)
        return {"game_id": game_id, "move_number": move_number}


def patched(store: Store) -> ExitStack:
    """Point every repository function at the in-memory store."""
    stack = ExitStack()
    f = "backend.services.friendship_service"
    c = "backend.services.challenge_service"
    m = "backend.services.multiplayer_service"
    g = "backend.services.game_service"

    targets = [
        (f, "get_between", store.get_between),
        (f, "get_by_id", store.friendship_by_id),
        (f, "create_friendship", store.create_friendship),
        (f, "set_status", store.set_friendship_status),
        (f, "reopen_request", store.reopen_request),
        (f, "delete_friendship", store.delete_friendship),
        (f, "list_by_status", store.list_by_status),
        (f, "list_requests", store.list_requests),
        (f, "get_many_by_ids", store.get_many_by_ids),
        (c, "are_friends", store.are_friends),
        (c, "create_challenge", store.create_challenge),
        (c, "get_by_id", store.challenge_by_id),
        (c, "get_pending_between", store.get_pending_between),
        (c, "set_status", store.set_challenge_status),
        (c, "attach_game", store.attach_game),
        (c, "list_for_user", store.list_challenges),
        (c, "expire_stale", store.expire_stale),
        (c, "get_game", store.get_game),
        (c, "get_many_by_ids", store.get_many_by_ids),
        (m, "create_multiplayer_game", store.create_multiplayer_game),
        (m, "get_game", store.get_game),
        (m, "list_for_user", store.list_games),
        (m, "finish_game", store.finish_game),
        (m, "set_draw_offer", store.set_draw_offer),
        (m, "set_turn_started", store.set_turn_started),
        (m, "update_clocks", store.update_clocks),
        (m, "add_chat", store.add_chat),
        (m, "list_chat", store.list_chat),
        (m, "get_many_by_ids", store.get_many_by_ids),
        (g, "get_game", store.get_game),
        (g, "update_game_state", store.update_game_state),
        (g, "insert_move", store.insert_move),
    ]
    for module, name, replacement in targets:
        stack.enter_context(patch(f"{module}.{name}", replacement))
    return stack


class SocialFlowTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.store = Store()

    async def _befriend(self):
        data, err = await friendship_service.send_request(None, ALICE, BOB)
        self.assertIsNone(err)
        _, err = await friendship_service.respond_to_request(
            None, BOB, data["friendship_id"], accept=True
        )
        self.assertIsNone(err)

    async def _start_game(self, time_control=None):
        await self._befriend()
        challenge, err = await challenge_service.create(
            None, ALICE, BOB, time_control_key=time_control, color_preference="white"
        )
        self.assertIsNone(err)
        accepted, err = await challenge_service.accept(
            None, BOB, challenge["challenge_id"]
        )
        self.assertIsNone(err)
        return accepted["game_id"]

    async def test_full_flow_request_to_finished_game(self):
        with patched(self.store):
            # 1-3: request, accept, both see each other.
            await self._befriend()
            alice_friends, _ = await friendship_service.list_friends(None, ALICE)
            bob_friends, _ = await friendship_service.list_friends(None, BOB)
            self.assertEqual(alice_friends["items"][0]["user"]["user_id"], BOB)
            self.assertEqual(bob_friends["items"][0]["user"]["user_id"], ALICE)

            # 13-15: challenge, accept, exactly one game.
            challenge, _ = await challenge_service.create(
                None, ALICE, BOB, color_preference="white"
            )
            accepted, err = await challenge_service.accept(
                None, BOB, challenge["challenge_id"]
            )
            self.assertIsNone(err)
            game_id = accepted["game_id"]
            self.assertEqual(len(self.store.games), 1)

            # 20-21: a legal move lands and flips the turn.
            state, err = await multiplayer_service.submit_move(
                None, game_id, ALICE, "e2e4"
            )
            self.assertIsNone(err)
            self.assertEqual(state["last_move"], "e2e4")
            self.assertFalse(state["your_turn"])

            bob_view, _ = await multiplayer_service.get_game_for_user(
                None, game_id, BOB
            )
            self.assertTrue(bob_view["your_turn"], "Black should now be to move")

            # 28-30: resignation ends it for both sides.
            resigned, err = await multiplayer_service.resign(None, game_id, BOB)
            self.assertIsNone(err)
            self.assertEqual(resigned["your_result"], "lost")
            alice_view, _ = await multiplayer_service.get_game_for_user(
                None, game_id, ALICE
            )
            self.assertEqual(alice_view["your_result"], "won")
            self.assertEqual(alice_view["status"], "completed")

            # 17: the finished game shows up in history, not active.
            active, _ = await multiplayer_service.list_games(None, ALICE, "active")
            history, _ = await multiplayer_service.list_games(None, ALICE, "completed")
            self.assertEqual(active["items"], [])
            self.assertEqual(len(history["items"]), 1)

    async def test_rejected_request_can_be_resent_and_then_accepted(self):
        with patched(self.store):
            first, _ = await friendship_service.send_request(None, ALICE, BOB)
            await friendship_service.respond_to_request(
                None, BOB, first["friendship_id"], accept=False
            )
            friends, _ = await friendship_service.list_friends(None, ALICE)
            self.assertEqual(friends["items"], [])

            again, err = await friendship_service.send_request(None, ALICE, BOB)
            self.assertIsNone(err)
            _, err = await friendship_service.respond_to_request(
                None, BOB, again["friendship_id"], accept=True
            )
            self.assertIsNone(err)
            friends, _ = await friendship_service.list_friends(None, ALICE)
            self.assertEqual(len(friends["items"]), 1)

    async def test_cancelled_request_disappears_for_the_recipient(self):
        with patched(self.store):
            sent, _ = await friendship_service.send_request(None, ALICE, BOB)
            incoming, _ = await friendship_service.list_incoming_requests(None, BOB)
            self.assertEqual(len(incoming["items"]), 1)

            await friendship_service.cancel_request(
                None, ALICE, sent["friendship_id"]
            )
            incoming, _ = await friendship_service.list_incoming_requests(None, BOB)
            self.assertEqual(incoming["items"], [])

    async def test_cannot_request_someone_who_is_already_a_friend(self):
        with patched(self.store):
            await self._befriend()
            data, err = await friendship_service.send_request(None, ALICE, BOB)
            self.assertIsNone(data)
            self.assertEqual(err, "You are already friends")

    async def test_unfriending_is_mutual(self):
        with patched(self.store):
            await self._befriend()
            _, err = await friendship_service.remove_friend(None, BOB, ALICE)
            self.assertIsNone(err)
            for user in (ALICE, BOB):
                friends, _ = await friendship_service.list_friends(None, user)
                self.assertEqual(friends["items"], [])

    async def test_two_rapid_challenges_yield_one_active_challenge(self):
        with patched(self.store):
            await self._befriend()
            first, err = await challenge_service.create(None, ALICE, BOB)
            self.assertIsNone(err)
            second, err = await challenge_service.create(None, ALICE, BOB)
            self.assertIsNone(second)
            self.assertEqual(
                err, "You already have a pending challenge with this player"
            )
            pending, _ = await challenge_service.list_outgoing(None, ALICE)
            self.assertEqual(len(pending["items"]), 1)
            self.assertEqual(pending["items"][0]["challenge_id"],
                             first["challenge_id"])

    async def test_double_accept_creates_only_one_game(self):
        with patched(self.store):
            await self._befriend()
            challenge, _ = await challenge_service.create(None, ALICE, BOB)
            first, err = await challenge_service.accept(
                None, BOB, challenge["challenge_id"]
            )
            self.assertIsNone(err)
            second, err = await challenge_service.accept(
                None, BOB, challenge["challenge_id"]
            )
            self.assertIsNone(second)
            self.assertEqual(err, "Challenge is no longer pending")
            self.assertEqual(len(self.store.games), 1)
            self.assertIsNotNone(first["game_id"])

    async def test_challenger_cannot_accept_their_own_challenge(self):
        with patched(self.store):
            await self._befriend()
            challenge, _ = await challenge_service.create(None, ALICE, BOB)
            data, err = await challenge_service.accept(
                None, ALICE, challenge["challenge_id"]
            )
            self.assertIsNone(data)
            self.assertEqual(err, "Not authorized")

    async def test_third_party_cannot_touch_a_challenge(self):
        with patched(self.store):
            await self._befriend()
            challenge, _ = await challenge_service.create(None, ALICE, BOB)
            for action in (challenge_service.accept, challenge_service.reject,
                           challenge_service.cancel):
                data, err = await action(None, MALLORY, challenge["challenge_id"])
                self.assertIsNone(data)
                self.assertEqual(err, "Not authorized")

    async def test_cannot_challenge_someone_who_is_not_a_friend(self):
        with patched(self.store):
            data, err = await challenge_service.create(None, ALICE, MALLORY)
            self.assertIsNone(data)
            self.assertEqual(err, "You can only challenge friends")

    async def test_out_of_turn_and_illegal_moves_are_refused(self):
        with patched(self.store):
            game_id = await self._start_game()

            # 22-23: Black cannot move first.
            data, err = await multiplayer_service.submit_move(
                None, game_id, BOB, "e7e5"
            )
            self.assertIsNone(data)
            self.assertEqual(err, "It is not your turn")

            # An impossible move is rejected by the engine.
            data, err = await multiplayer_service.submit_move(
                None, game_id, ALICE, "e2e5"
            )
            self.assertIsNone(data)
            self.assertEqual(err, "Illegal move")

            # The position is untouched by either failure.
            state, _ = await multiplayer_service.get_game_for_user(
                None, game_id, ALICE
            )
            self.assertEqual(state["game_version"], 0)
            self.assertEqual(state["current_fen"], chess.Board().fen())

    async def test_outsider_cannot_read_or_alter_a_game(self):
        with patched(self.store):
            game_id = await self._start_game()
            for coro in (
                multiplayer_service.get_game_for_user(None, game_id, MALLORY),
                multiplayer_service.submit_move(None, game_id, MALLORY, "e2e4"),
                multiplayer_service.resign(None, game_id, MALLORY),
                multiplayer_service.offer_draw(None, game_id, MALLORY),
                multiplayer_service.get_chat(None, game_id, MALLORY),
            ):
                data, err = await coro
                self.assertIsNone(data)
                self.assertEqual(err, "Not authorized")

    async def test_reconnecting_player_sees_authoritative_state(self):
        with patched(self.store):
            game_id = await self._start_game()
            await multiplayer_service.submit_move(None, game_id, ALICE, "e2e4")
            await multiplayer_service.submit_move(None, game_id, BOB, "e7e5")

            # A client coming back cold reads the same position as the server.
            fresh, err = await multiplayer_service.get_game_for_user(
                None, game_id, ALICE
            )
            self.assertIsNone(err)
            board = chess.Board()
            board.push_uci("e2e4")
            board.push_uci("e7e5")
            self.assertEqual(fresh["current_fen"], board.fen())
            self.assertEqual(fresh["game_version"], 2)
            self.assertTrue(fresh["your_turn"])

    async def test_stale_version_is_rejected_by_the_concurrency_guard(self):
        with patched(self.store):
            game_id = await self._start_game()
            await multiplayer_service.submit_move(
                None, game_id, ALICE, "e2e4", expected_version=0
            )
            await multiplayer_service.submit_move(None, game_id, BOB, "e7e5")
            # Alice replays against the version she had before Bob moved.
            data, err = await multiplayer_service.submit_move(
                None, game_id, ALICE, "g1f3", expected_version=0
            )
            self.assertIsNone(data)
            self.assertIn("Version mismatch", err)

    async def test_draw_offer_and_acceptance(self):
        with patched(self.store):
            game_id = await self._start_game()
            _, err = await multiplayer_service.offer_draw(None, game_id, ALICE)
            self.assertIsNone(err)

            data, err = await multiplayer_service.respond_to_draw(
                None, game_id, ALICE, accept=True
            )
            self.assertIsNone(data)
            self.assertEqual(err, "You cannot answer your own draw offer")

            accepted, err = await multiplayer_service.respond_to_draw(
                None, game_id, BOB, accept=True
            )
            self.assertIsNone(err)
            self.assertEqual(accepted["your_result"], "draw")
            alice_view, _ = await multiplayer_service.get_game_for_user(
                None, game_id, ALICE
            )
            self.assertEqual(alice_view["your_result"], "draw")

    async def test_declined_draw_leaves_the_game_running(self):
        with patched(self.store):
            game_id = await self._start_game()
            await multiplayer_service.offer_draw(None, game_id, ALICE)
            resumed, err = await multiplayer_service.respond_to_draw(
                None, game_id, BOB, accept=False
            )
            self.assertIsNone(err)
            self.assertEqual(resumed["status"], "active")
            self.assertIsNone(resumed["draw_offer_by"])
            _, err = await multiplayer_service.submit_move(
                None, game_id, ALICE, "e2e4"
            )
            self.assertIsNone(err)

    async def test_checkmate_ends_the_game_automatically(self):
        with patched(self.store):
            game_id = await self._start_game()
            # Fool's mate: 1. f3 e5 2. g4 Qh4#
            for user, uci in ((ALICE, "f2f3"), (BOB, "e7e5"),
                              (ALICE, "g2g4"), (BOB, "d8h4")):
                state, err = await multiplayer_service.submit_move(
                    None, game_id, user, uci
                )
                self.assertIsNone(err, f"{uci} should be legal")

            self.assertEqual(state["status"], "completed")
            self.assertEqual(state["end_reason"], "checkmate")
            self.assertEqual(state["your_result"], "won")
            loser, _ = await multiplayer_service.get_game_for_user(
                None, game_id, ALICE
            )
            self.assertEqual(loser["your_result"], "lost")

    async def test_no_moves_accepted_after_the_game_ends(self):
        with patched(self.store):
            game_id = await self._start_game()
            await multiplayer_service.resign(None, game_id, ALICE)
            data, err = await multiplayer_service.submit_move(
                None, game_id, BOB, "e2e4"
            )
            self.assertIsNone(data)
            self.assertEqual(err, "Game is already finished")

    async def test_chat_is_shared_between_the_two_players(self):
        with patched(self.store):
            game_id = await self._start_game()
            await multiplayer_service.post_chat(None, game_id, ALICE, "good luck")
            await multiplayer_service.post_chat(None, game_id, BOB, "you too")
            history, err = await multiplayer_service.get_chat(None, game_id, BOB)
            self.assertIsNone(err)
            self.assertEqual([m["text"] for m in history["items"]],
                             ["good luck", "you too"])

    async def test_rematch_swaps_colours(self):
        with patched(self.store):
            game_id = await self._start_game()
            await multiplayer_service.resign(None, game_id, ALICE)
            rematch, err = await challenge_service.create_rematch(
                None, ALICE, game_id
            )
            self.assertIsNone(err)
            # Alice had White, so the rematch offers her Black.
            self.assertEqual(rematch["color_preference"], "black")

    async def test_rematch_is_refused_while_the_game_is_live(self):
        with patched(self.store):
            game_id = await self._start_game()
            data, err = await challenge_service.create_rematch(None, ALICE, game_id)
            self.assertIsNone(data)
            self.assertEqual(err, "Finish the current game first")

    async def test_colour_assignment_is_consistent_across_both_views(self):
        with patched(self.store):
            game_id = await self._start_game()
            alice, _ = await multiplayer_service.get_game_for_user(
                None, game_id, ALICE
            )
            bob, _ = await multiplayer_service.get_game_for_user(None, game_id, BOB)
            self.assertEqual(alice["your_color"], "white")
            self.assertEqual(alice["opponent_color"], "black")
            self.assertEqual(bob["your_color"], "black")
            self.assertEqual(bob["opponent_color"], "white")
            self.assertNotEqual(alice["your_color"], bob["your_color"])

    async def test_timed_game_starts_both_clocks(self):
        with patched(self.store):
            game_id = await self._start_game(time_control="blitz_5_0")
            state, _ = await multiplayer_service.get_game_for_user(
                None, game_id, ALICE
            )
            self.assertEqual(state["time_control"]["key"], "blitz_5_0")
            self.assertEqual(state["clocks"][ALICE]["remaining_ms"], 300000)
            self.assertEqual(state["clocks"][BOB]["remaining_ms"], 300000)

    async def test_increment_is_added_after_a_move(self):
        with patched(self.store):
            game_id = await self._start_game(time_control="blitz_3_2")
            await multiplayer_service.submit_move(None, game_id, ALICE, "e2e4")
            game = self.store.games[game_id]
            # 180s start, ~0s spent, +2s increment.
            self.assertGreater(game["clocks"][ALICE]["remaining_ms"], 180000)


if __name__ == "__main__":
    unittest.main()
