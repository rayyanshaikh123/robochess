import unittest

from pi_agent.calibration import (
    CORNER_EXPANSION,
    CalibrationError,
    calibrate_from_rooks,
    expand_from_centroid,
    order_quad,
    piece_base_point,
)


def rook(name, x, y, conf=0.9, height=40.0, width=20.0):
    """A detection whose foot sits at (x, y)."""
    return {
        "class_name": name,
        "confidence": conf,
        "bbox": [x - width / 2, y - height, x + width / 2, y],
        "center": (x, y - height / 2),
    }


def board(white_corners, black_corners):
    return ([rook("white_rook", *p) for p in white_corners]
            + [rook("black_rook", *p) for p in black_corners])


TL, TR, BR, BL = (100.0, 100.0), (400.0, 100.0), (400.0, 400.0), (100.0, 400.0)


class BasePointTests(unittest.TestCase):
    def test_uses_bbox_foot_not_centre(self):
        # The piece is tall, so its bbox centre floats above the board plane.
        self.assertEqual(piece_base_point(rook("white_rook", 200.0, 300.0)), (200.0, 300.0))

    def test_falls_back_to_centre_without_bbox(self):
        self.assertEqual(piece_base_point({"center": (5.0, 6.0)}), (5.0, 6.0))

    def test_rejects_unusable_detection(self):
        with self.assertRaises(CalibrationError):
            piece_base_point({"class_name": "white_rook"})


class GeometryHelperTests(unittest.TestCase):
    def test_order_quad_sorts_clockwise_from_top_left(self):
        self.assertEqual(order_quad([BR, BL, TR, TL]), [TL, TR, BR, BL])

    def test_order_quad_rejects_degenerate_points(self):
        with self.assertRaises(CalibrationError):
            order_quad([TL, TL, BR, BL])

    def test_expansion_pushes_corners_outward_about_centroid(self):
        out = expand_from_centroid([TL, TR, BR, BL], CORNER_EXPANSION)
        # Centroid is unchanged; every corner moves away from it.
        self.assertAlmostEqual(sum(p[0] for p in out) / 4, 250.0)
        self.assertLess(out[0][0], TL[0])
        self.assertGreater(out[2][0], BR[0])


class RookCalibrationTests(unittest.TestCase):
    def test_white_at_bottom_needs_no_rotation(self):
        result = calibrate_from_rooks(board([BL, BR], [TL, TR]))
        self.assertEqual(result["rotation_cw"], 0)
        self.assertEqual(result["board_orientation"], "white_bottom")
        self.assertEqual(result["white_edge"], "bottom")

    def test_white_at_top_is_upside_down(self):
        self.assertEqual(calibrate_from_rooks(board([TL, TR], [BL, BR]))["rotation_cw"], 180)

    def test_white_on_left_rotates_counter_clockwise(self):
        # Left edge must travel to the bottom, i.e. 90 CCW == 270 CW.
        self.assertEqual(calibrate_from_rooks(board([TL, BL], [TR, BR]))["rotation_cw"], 270)

    def test_white_on_right_rotates_clockwise(self):
        self.assertEqual(calibrate_from_rooks(board([TR, BR], [TL, BL]))["rotation_cw"], 90)

    def test_corners_extend_beyond_the_rook_feet(self):
        result = calibrate_from_rooks(board([BL, BR], [TL, TR]))
        corners = result["corners"]
        self.assertEqual(len(corners), 4)
        # Board edge lies half a square outside the corner-square centres.
        self.assertLess(corners[0][0], TL[0])
        self.assertLess(corners[0][1], TL[1])
        self.assertGreater(corners[2][0], BR[0])
        self.assertGreater(corners[2][1], BR[1])

    def test_missing_rooks_is_an_error(self):
        with self.assertRaises(CalibrationError):
            calibrate_from_rooks(board([BL], [TL, TR]))

    def test_rooks_not_on_one_edge_is_an_error(self):
        # Diagonal white rooks mean the board is not in its start position.
        with self.assertRaises(CalibrationError):
            calibrate_from_rooks(board([TL, BR], [TR, BL]))

    def test_extra_rooks_use_the_most_confident(self):
        dets = board([BL, BR], [TL, TR]) + [rook("white_rook", 250.0, 250.0, conf=0.1)]
        self.assertEqual(calibrate_from_rooks(dets)["rotation_cw"], 0)

    def test_reports_weakest_rook_confidence(self):
        dets = board([BL, BR], [TL, TR])
        dets[0]["confidence"] = 0.42
        self.assertAlmostEqual(calibrate_from_rooks(dets)["min_confidence"], 0.42)


if __name__ == "__main__":
    unittest.main()
