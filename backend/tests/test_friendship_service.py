import unittest
from unittest.mock import AsyncMock, patch

from pymongo.errors import DuplicateKeyError

from backend.repositories.friendship_repo import pair_key
from backend.services.friendship_service import (
    cancel_request,
    list_friends,
    remove_friend,
    respond_to_request,
    send_request,
)

ALICE = "alice"
BOB = "bob"

SERVICE = "backend.services.friendship_service"


def friendship_row(requester, addressee, status="pending", row_id="f1"):
    user_a, user_b = pair_key(requester, addressee)
    return {
        "_id": row_id,
        "user_a": user_a,
        "user_b": user_b,
        "requester_id": requester,
        "addressee_id": addressee,
        "status": status,
        "created_at": None,
        "updated_at": None,
    }


def profiles(*user_ids):
    return {uid: {"_id": uid, "display_name": uid.title(), "rating": 1200} for uid in user_ids}


class SendRequestTests(unittest.IsolatedAsyncioTestCase):
    async def test_cannot_friend_yourself(self):
        data, err = await send_request(None, ALICE, ALICE)
        self.assertIsNone(data)
        self.assertEqual(err, "You cannot send a friend request to yourself")

    async def test_unknown_user_is_rejected(self):
        with patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={})):
            data, err = await send_request(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "User not found")

    async def test_creates_a_pending_request(self):
        created = friendship_row(ALICE, BOB)
        with patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(BOB))), \
             patch(f"{SERVICE}.get_between", AsyncMock(return_value=None)), \
             patch(f"{SERVICE}.create_friendship", AsyncMock(return_value=created)):
            data, err = await send_request(None, ALICE, BOB)
        self.assertIsNone(err)
        self.assertEqual(data["status"], "pending")
        self.assertTrue(data["requested_by_me"])
        self.assertEqual(data["user"]["user_id"], BOB)

    async def test_duplicate_pending_request_is_rejected(self):
        existing = friendship_row(ALICE, BOB, "pending")
        with patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(BOB))), \
             patch(f"{SERVICE}.get_between", AsyncMock(return_value=existing)):
            data, err = await send_request(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "Friend request already pending")

    async def test_existing_friendship_is_rejected(self):
        existing = friendship_row(ALICE, BOB, "accepted")
        with patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(BOB))), \
             patch(f"{SERVICE}.get_between", AsyncMock(return_value=existing)):
            data, err = await send_request(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "You are already friends")

    async def test_reverse_pending_request_auto_accepts(self):
        # Bob already asked Alice; Alice asking back means they are friends.
        existing = friendship_row(BOB, ALICE, "pending")
        accepted = friendship_row(BOB, ALICE, "accepted")
        set_status = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(BOB))), \
             patch(f"{SERVICE}.get_between", AsyncMock(return_value=existing)), \
             patch(f"{SERVICE}.set_status", set_status), \
             patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=accepted)):
            data, err = await send_request(None, ALICE, BOB)
        self.assertIsNone(err)
        self.assertTrue(data["auto_accepted"])
        self.assertEqual(data["status"], "accepted")
        set_status.assert_awaited_once()

    async def test_rejected_request_can_be_sent_again(self):
        existing = friendship_row(ALICE, BOB, "rejected")
        reopened = friendship_row(ALICE, BOB, "pending")
        reopen = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(BOB))), \
             patch(f"{SERVICE}.get_between", AsyncMock(return_value=existing)), \
             patch(f"{SERVICE}.reopen_request", reopen), \
             patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=reopened)):
            data, err = await send_request(None, ALICE, BOB)
        self.assertIsNone(err)
        self.assertEqual(data["status"], "pending")
        reopen.assert_awaited_once()

    async def test_race_on_unique_index_is_reported_cleanly(self):
        with patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(BOB))), \
             patch(f"{SERVICE}.get_between", AsyncMock(return_value=None)), \
             patch(f"{SERVICE}.create_friendship", AsyncMock(side_effect=DuplicateKeyError("dup"))):
            data, err = await send_request(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "Friend request already pending")


class RespondTests(unittest.IsolatedAsyncioTestCase):
    async def test_addressee_can_accept(self):
        row = friendship_row(ALICE, BOB, "pending")
        accepted = friendship_row(ALICE, BOB, "accepted")
        with patch(f"{SERVICE}.get_by_id", AsyncMock(side_effect=[row, accepted])), \
             patch(f"{SERVICE}.set_status", AsyncMock(return_value=True)), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value=profiles(ALICE))):
            data, err = await respond_to_request(None, BOB, "f1", accept=True)
        self.assertIsNone(err)
        self.assertEqual(data["status"], "accepted")

    async def test_requester_cannot_accept_their_own_request(self):
        row = friendship_row(ALICE, BOB, "pending")
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=row)):
            data, err = await respond_to_request(None, ALICE, "f1", accept=True)
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_third_party_cannot_respond(self):
        row = friendship_row(ALICE, BOB, "pending")
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=row)):
            data, err = await respond_to_request(None, "mallory", "f1", accept=True)
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_already_answered_request_cannot_be_answered_again(self):
        row = friendship_row(ALICE, BOB, "accepted")
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=row)):
            data, err = await respond_to_request(None, BOB, "f1", accept=False)
        self.assertIsNone(data)
        self.assertEqual(err, "Friend request is no longer pending")

    async def test_missing_request(self):
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=None)):
            data, err = await respond_to_request(None, BOB, "nope", accept=True)
        self.assertIsNone(data)
        self.assertEqual(err, "Friend request not found")


class CancelAndRemoveTests(unittest.IsolatedAsyncioTestCase):
    async def test_requester_can_cancel(self):
        row = friendship_row(ALICE, BOB, "pending")
        delete = AsyncMock(return_value=True)
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=row)), \
             patch(f"{SERVICE}.delete_friendship", delete):
            data, err = await cancel_request(None, ALICE, "f1")
        self.assertIsNone(err)
        self.assertTrue(data["cancelled"])
        self.assertEqual(data["user_id"], BOB)
        delete.assert_awaited_once()

    async def test_addressee_cannot_cancel(self):
        row = friendship_row(ALICE, BOB, "pending")
        with patch(f"{SERVICE}.get_by_id", AsyncMock(return_value=row)):
            data, err = await cancel_request(None, BOB, "f1")
        self.assertIsNone(data)
        self.assertEqual(err, "Not authorized")

    async def test_either_party_can_unfriend(self):
        row = friendship_row(ALICE, BOB, "accepted")
        with patch(f"{SERVICE}.get_between", AsyncMock(return_value=row)), \
             patch(f"{SERVICE}.delete_friendship", AsyncMock(return_value=True)):
            data, err = await remove_friend(None, BOB, ALICE)
        self.assertIsNone(err)
        self.assertTrue(data["removed"])

    async def test_cannot_unfriend_a_non_friend(self):
        with patch(f"{SERVICE}.get_between", AsyncMock(return_value=None)):
            data, err = await remove_friend(None, ALICE, BOB)
        self.assertIsNone(data)
        self.assertEqual(err, "You are not friends with this user")


class ListingTests(unittest.IsolatedAsyncioTestCase):
    async def test_friends_list_never_exposes_email(self):
        row = friendship_row(ALICE, BOB, "accepted")
        user = {"_id": BOB, "display_name": "Bob", "rating": 1300,
                "email": "bob@example.com", "password_hash": "secret"}
        with patch(f"{SERVICE}.list_by_status", AsyncMock(return_value=[row])), \
             patch(f"{SERVICE}.get_many_by_ids", AsyncMock(return_value={BOB: user})):
            data, err = await list_friends(None, ALICE)
        self.assertIsNone(err)
        serialized = data["items"][0]["user"]
        self.assertEqual(serialized["display_name"], "Bob")
        self.assertNotIn("email", serialized)
        self.assertNotIn("password_hash", serialized)


if __name__ == "__main__":
    unittest.main()
