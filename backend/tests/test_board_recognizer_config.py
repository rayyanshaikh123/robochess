import os
import unittest
from unittest.mock import patch

from backend.board_recognizer import BoardRecognizer, parse_cloud_model_id


class BoardRecognizerConfigTests(unittest.TestCase):
    def test_parses_roboflow_url_model_id(self):
        self.assertEqual(
            parse_cloud_model_id("https://detect.roboflow.com/chess-pieces/3"),
            "chess-pieces/3",
        )

    def test_cloud_configuration_does_not_discard_local_candidate(self):
        env = {
            "ROBOCHESS_ROBOFLOW_ENABLED": "1",
            "ROBOCHESS_ROBOFLOW_MODEL_URL": "https://detect.roboflow.com/chess-pieces/3",
            "ROBOCHESS_ROBOFLOW_API_KEY": "test-key",
        }
        with patch.dict(os.environ, env, clear=False), patch.object(
            BoardRecognizer, "_load_local_model", return_value=None
        ) as load_local:
            recognizer = BoardRecognizer("/tmp/missing-best.pt")
            self.assertIsNotNone(recognizer.cloud_model)
            self.assertIsNone(recognizer.model)
            self.assertTrue(recognizer.status()["cloud_configured"])
            load_local.assert_not_called()


if __name__ == "__main__":
    unittest.main()
