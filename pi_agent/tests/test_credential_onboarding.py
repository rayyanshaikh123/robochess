import json
import unittest
from tempfile import TemporaryDirectory
from unittest.mock import patch

from pi_agent.gatt_server import GattServer
from pi_agent.ble_protocol import decode_message, envelope
from pi_agent.provisioning_store import ProvisioningStore


class CredentialOnboardingTests(unittest.TestCase):
    def test_credential_message_contains_secret_and_store_round_trips_it(self):
        with TemporaryDirectory() as directory:
            store = ProvisioningStore(f"{directory}/provisioning.json")
            message = envelope(
                "onboarding.token",
                "board-001",
                onboarding_token="token-value",
                device_secret="secret-value",
            )
            received = {}

            def on_control(payload):
                received.update(payload)
                store.set_credentials(
                    payload["device_id"], payload["data"]["device_secret"]
                )
                return {"status": "token_saved"}

            gatt = GattServer("board-001", on_control=on_control)
            replies = gatt.handle_control(json.dumps(message).encode())
            response = decode_message(replies[0])

            self.assertEqual(response["data"]["status"], "token_saved")
            self.assertEqual(received["data"]["device_secret"], "secret-value")
            self.assertEqual(store.get_credentials(), ("board-001", "secret-value"))


if __name__ == "__main__":
    unittest.main()
