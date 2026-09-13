import ast
import unittest

import chess

from pi_agent.vision_recognizer import BoardRecognizer, normalize_class_name


class PiVisionBoundaryTests(unittest.TestCase):
    def test_pi_vision_module_does_not_import_backend(self):
        with open("pi_agent/vision_recognizer.py", encoding="utf-8") as handle:
            source = handle.read()
        tree = ast.parse(source)
        imports = [node for node in ast.walk(tree) if isinstance(node, (ast.Import, ast.ImportFrom))]
        imported = []
        for node in imports:
            if isinstance(node, ast.Import):
                imported.extend(alias.name for alias in node.names)
            elif node.module:
                imported.append(node.module)
        self.assertFalse(any(name == "backend" or name.startswith("backend.") for name in imported))

    def test_class_labels_keep_roboflow_colour(self):
        self.assertEqual(normalize_class_name("R"), "white_rook")
        self.assertEqual(normalize_class_name("r"), "black_rook")
        self.assertEqual(normalize_class_name("White Queen"), "white_queen")

    def test_legal_move_inference_stays_in_pi_runtime(self):
        recognizer = BoardRecognizer.__new__(BoardRecognizer)
        board = chess.Board()
        state = recognizer.board_to_state_dict(board.copy(stack=False))
        state["e2"] = None
        state["e4"] = "white_pawn"
        move, score, gap = recognizer.infer_move_from_state(board, state, min_score=64, min_gap=1)
        self.assertEqual(move.uci(), "e2e4")
        self.assertGreaterEqual(score, 64)
        self.assertGreaterEqual(gap, 1)


if __name__ == "__main__":
    unittest.main()
