import os
import unittest
from tempfile import TemporaryDirectory

from pi_agent.provisioning_store import ProvisioningStore


class ProvisioningStoreTests(unittest.TestCase):
    def test_credentials_round_trip_with_restricted_permissions(self):
        with TemporaryDirectory() as directory:
            path = os.path.join(directory, "provisioning.json")
            store = ProvisioningStore(path)
            store.set_credentials("board-001", "secret-value")

            self.assertEqual(store.get_credentials(), ("board-001", "secret-value"))
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)

    def test_clearing_token_preserves_credentials(self):
        with TemporaryDirectory() as directory:
            store = ProvisioningStore(os.path.join(directory, "provisioning.json"))
            store.set_credentials("board-001", "secret-value")
            store.set_onboarding_token("token-value")
            store.clear_onboarding_token()

            self.assertEqual(store.get_credentials(), ("board-001", "secret-value"))
            self.assertIsNone(store.load().get("onboarding_token"))


if __name__ == "__main__":
    unittest.main()
