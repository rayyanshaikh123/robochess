from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import AsyncMock, patch

from backend.core.security import hash_password, verify_password
from backend.services.device_service import claim_device, create_onboarding_token


class DeviceBootstrapTests(unittest.IsolatedAsyncioTestCase):
    async def test_missing_stable_id_is_registered_with_one_time_secret(self):
        created = {}

        async def create_device(_db, **kwargs):
            created.update(kwargs)
            return kwargs

        with patch("backend.services.device_service.get_by_device_id", AsyncMock(return_value=None)), \
             patch("backend.services.device_service.create_device", create_device), \
             patch("backend.services.device_service.save_onboarding_token", AsyncMock()):
            data, error = await create_onboarding_token(None, "user-1", "board-001")

        self.assertIsNone(error)
        self.assertEqual(data["device_id"], "board-001")
        self.assertTrue(data["device_secret"])
        self.assertTrue(verify_password(data["device_secret"], created["device_secret_hash"]))

    async def test_linked_device_is_rejected_without_rotating_secret(self):
        device = {"device_id": "board-001", "user_id": "other-user"}
        with patch("backend.services.device_service.get_by_device_id", AsyncMock(return_value=device)), \
             patch("backend.services.device_service.update_device_secret", AsyncMock()) as rotate:
            data, error = await create_onboarding_token(None, "user-1", "board-001")

        self.assertIsNone(data)
        self.assertEqual(error, "Device already linked")
        rotate.assert_not_awaited()

    async def test_claim_accepts_naive_database_expiry_and_consumes_token(self):
        token = "onboarding-token"
        device = {
            "device_id": "board-001",
            "onboarding_token_hash": hash_password(token),
            "onboarding_token_expires_at": datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=5),
            "onboarding_user_id": "user-1",
            "user_id": None,
        }
        with patch("backend.services.device_service.get_by_device_id", AsyncMock(return_value=device)), \
             patch("backend.services.device_service.consume_onboarding_token", AsyncMock(return_value=True)), \
             patch("backend.services.device_service.link_user", AsyncMock()) as link, \
             patch("backend.services.device_service.update_device_metadata", AsyncMock()):
            data, error = await claim_device(None, "board-001", token)

        self.assertIsNone(error)
        self.assertEqual(data, {"device_id": "board-001", "status": "online"})
        link.assert_awaited_once_with(None, "board-001", "user-1")


if __name__ == "__main__":
    unittest.main()
