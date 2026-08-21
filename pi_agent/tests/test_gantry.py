import unittest

import chess

from pi_agent.geometry import (
    FILES,
    GRAVEYARD_CAPACITY,
    LATTICE_OFFSET_MM,
    RANKS,
    BoardGeometry,
    GeometryError,
)
from pi_agent.uno_controller import (
    GantryStatus,
    SimulatedTransport,
    UnoController,
    UnoError,
    motion_plan,
)

ALL_SQUARES = [f + r for f in FILES for r in RANKS]


class GeometryTests(unittest.TestCase):
    def setUp(self):
        self.geo = BoardGeometry()

    def test_square_mm_round_trip_for_every_square(self):
        for square in ALL_SQUARES:
            x, y = self.geo.square_to_mm(square)
            self.assertEqual(self.geo.mm_to_square(x, y), square)

    def test_every_square_is_reachable(self):
        for square in ALL_SQUARES:
            x, y = self.geo.square_to_mm(square)
            self.assertTrue(self.geo.within_limits(x, y), f"{square} outside envelope")

    def test_orientation_flags_mirror_the_mapping(self):
        flipped = BoardGeometry(files_reversed=False, ranks_reversed=False)
        # a1 sits at opposite ends of X depending on the file flag.
        self.assertNotEqual(self.geo.square_to_mm("a1")[0], flipped.square_to_mm("a1")[0])
        # Round-tripping must still hold under the flipped orientation.
        for square in ALL_SQUARES:
            x, y = flipped.square_to_mm(square)
            self.assertEqual(flipped.mm_to_square(x, y), square)

    def test_rejects_invalid_square(self):
        for bad in ("", "j1", "a9", "e", "e44"):
            with self.assertRaises(GeometryError):
                self.geo.square_to_mm(bad)

    def test_straight_and_diagonal_moves_go_direct(self):
        for from_sq, to_sq in (("e2", "e4"), ("a1", "a8"), ("c1", "h6")):
            self.assertEqual(self.geo.plan_board_path(from_sq, to_sq),
                             [self.geo.square_to_mm(to_sq)])

    def test_knight_move_routes_along_gridlines(self):
        path = self.geo.plan_board_path("g1", "f3")
        # Sidestep onto a gridline, run the long leg, then step into centre.
        self.assertEqual(len(path), 3)
        self.assertEqual(path[-1], self.geo.square_to_mm("f3"))
        # The first leg must sit half a square off the source centre -- on the
        # gridline -- or the piece would be dragged through occupied squares.
        fx, fy = self.geo.square_to_mm("g1")
        self.assertAlmostEqual(abs(path[0][0] - fx), LATTICE_OFFSET_MM)
        self.assertAlmostEqual(path[0][1], fy)
        for x, y in path:
            self.assertTrue(self.geo.within_limits(x, y))

    def test_knight_sidestep_follows_millimetre_delta(self):
        # With files_reversed a rising file index means a falling x, so an
        # index-derived sign would sidestep the wrong way.
        path = self.geo.plan_board_path("g1", "f3")
        start_x, _ = self.geo.square_to_mm("g1")
        target_x, _ = self.geo.square_to_mm("f3")
        step_x = path[0][0]
        self.assertEqual(step_x > start_x, target_x > start_x)

    def test_graveyard_slots_are_distinct_and_reachable(self):
        seen = set()
        for index in range(GRAVEYARD_CAPACITY):
            slot = self.geo.graveyard_slot_mm(index)
            self.assertNotIn(slot, seen)
            seen.add(slot)
            self.assertTrue(self.geo.within_limits(*slot))

    def test_graveyard_slot_out_of_range(self):
        with self.assertRaises(GeometryError):
            self.geo.graveyard_slot_mm(GRAVEYARD_CAPACITY)

    def test_graveyard_path_clears_the_board_before_moving_along_y(self):
        slot = self.geo.graveyard_slot_mm(0)
        path = self.geo.plan_graveyard_path("d4", slot)
        self.assertEqual(path[-1], slot)
        for x, y in path:
            self.assertTrue(self.geo.within_limits(x, y))


class StatusParsingTests(unittest.TestCase):
    def test_parses_full_status_line(self):
        status = GantryStatus.parse(["OK X=12.50 Y=300.00 HOMED=1 MAG=OFF LIMX=0 LIMY=1"])
        self.assertEqual(status.x_mm, 12.5)
        self.assertEqual(status.y_mm, 300.0)
        self.assertTrue(status.homed)
        self.assertFalse(status.magnet_on)
        self.assertTrue(status.limit_y)

    def test_tolerates_unparseable_line(self):
        self.assertIsNone(GantryStatus.parse(["OK PONG v2"]).x_mm)


class UnoControllerTests(unittest.TestCase):
    def _controller(self, **kwargs):
        transport = SimulatedTransport(**kwargs)
        return UnoController(transport, retries=0), transport

    def test_quiet_move_sequence_toggles_magnet_around_the_drag(self):
        uno, transport = self._controller()
        board = chess.Board()
        uno.execute(motion_plan(board, chess.Move.from_uci("e2e4")))
        verbs = [c.split()[0] for c in transport.commands]
        self.assertEqual(verbs.count("MAG"), 2)
        # Magnet on only after arriving at the source square.
        self.assertEqual(verbs[0], "MOVEXY")
        self.assertEqual(transport.commands[1], "MAG ON")
        self.assertEqual(verbs[-1], "MOVEXY")  # parked at the end

    def test_capture_removes_the_taken_piece_before_moving(self):
        uno, transport = self._controller()
        board = chess.Board("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        move = chess.Move.from_uci("e4d5")
        self.assertTrue(board.is_capture(move))
        uno.execute(motion_plan(board, move))
        # Two drags: the captured piece to the strip, then the capturing pawn.
        self.assertEqual([c.split()[0] for c in transport.commands].count("MAG"), 4)
        graveyard_x, _ = uno.geometry.graveyard_slot_mm(0)
        self.assertTrue(any(f"MOVEXY {graveyard_x:.2f}" in c for c in transport.commands))

    def test_castling_moves_the_rook_too(self):
        uno, transport = self._controller()
        board = chess.Board("rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1")
        uno.execute(motion_plan(board, chess.Move.from_uci("e1g1")))
        self.assertEqual([c.split()[0] for c in transport.commands].count("MAG"), 4)

    def test_promotion_is_flagged_for_a_human(self):
        uno, _ = self._controller()
        board = chess.Board("8/P6k/8/8/8/8/8/7K w - - 0 1")
        uno.execute(motion_plan(board, chess.Move.from_uci("a7a8q")))
        self.assertTrue(any("a8" in action for action in uno.manual_actions))

    def test_error_reply_raises_and_releases_the_magnet(self):
        uno, transport = self._controller(fail=True)
        with self.assertRaises(UnoError):
            uno.execute(motion_plan(chess.Board(), chess.Move.from_uci("e2e4")))
        self.assertIn("MAG OFF", transport.commands)

    def test_illegal_move_is_refused_at_planning_time(self):
        with self.assertRaises(UnoError):
            motion_plan(chess.Board(), chess.Move.from_uci("e2e5"))

    def test_move_outside_envelope_is_refused(self):
        uno, _ = self._controller()
        with self.assertRaises(UnoError):
            uno.move_to(9999.0, 0.0)

    def test_graveyard_capacity_is_enforced(self):
        uno, _ = self._controller()
        uno._graveyard_used = GRAVEYARD_CAPACITY
        board = chess.Board("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        with self.assertRaises(UnoError):
            uno.execute(motion_plan(board, chess.Move.from_uci("e4d5")))

    def test_status_and_ping_round_trip(self):
        uno, _ = self._controller()
        self.assertTrue(uno.ping())
        self.assertTrue(uno.status()["homed"])


if __name__ == "__main__":
    unittest.main()
