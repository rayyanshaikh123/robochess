import json
import unittest

from .ble_protocol import Message, ProtocolError, SessionProtocol


class ProtocolTests(unittest.TestCase):
    def test_round_trip_and_payload(self):
        message = Message("state", seq=2, payload={"state": "player_turn"})
        decoded = Message.decode(message.encode())
        self.assertEqual(decoded.type, "state")
        self.assertEqual(decoded.payload["state"], "player_turn")

    def test_rejects_version(self):
        with self.assertRaises(ProtocolError):
            Message.decode(json.dumps({"version": 99, "type": "state"}))

    def test_duplicate_request_is_idempotent(self):
        calls = []

        def handler(message):
            calls.append(message.type)
            return Message("ack", payload={"ok": True})

        protocol = SessionProtocol(handler)
        raw = Message("session.start", seq=1, request_id="same").encode()
        self.assertEqual(protocol.handle(raw), protocol.handle(raw))
        self.assertEqual(calls, ["session.start"])

    def test_out_of_order_is_rejected(self):
        protocol = SessionProtocol(lambda _: Message("ack"))
        protocol.handle(Message("one", seq=2).encode())
        result = json.loads(protocol.handle(Message("two", seq=1).encode()))
        self.assertIn("out-of-order", result["reason"])


if __name__ == "__main__":
    unittest.main()
