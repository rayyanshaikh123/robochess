import unittest
from unittest.mock import AsyncMock, patch

from backend.services.device_service import create_onboarding_token
from backend.core.security import verify_password


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


if __name__ == "__main__":
    unittest.main()
