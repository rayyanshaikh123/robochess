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

    def test_capture_move_detected_in_state_and_occupancy(self):
        recognizer = BoardRecognizer.__new__(BoardRecognizer)
        # 1. e4 d5, White to move, exd5 capture available
        board = chess.Board("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        move_capture = chess.Move.from_uci("e4d5")
        board_after = board.copy()
        board_after.push(move_capture)

        # Perfect state match
        state = recognizer.board_to_state_dict(board_after)
        move, score, gap = recognizer.infer_move_from_state(board, state)
        self.assertEqual(move, move_capture)
        self.assertEqual(score, 64)

        # Occupancy match (gap is 1 between capture and alternative quiet move e4e5)
        occ = recognizer.board_to_occupancy_state(board_after)
        move_occ, score_occ, gap_occ = recognizer.infer_move_from_occupancy(board, occ)
        self.assertEqual(move_occ, move_capture)
        self.assertEqual(score_occ, 64)

        # Noisy state match (d5 detected as generic "pawn" without color prefix)
        state_noisy = state.copy()
        state_noisy["d5"] = "pawn"
        move_noisy, _, _ = recognizer.infer_move_from_state(board, state_noisy)
        self.assertEqual(move_noisy, move_capture)

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
