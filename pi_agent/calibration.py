"""Automatic board calibration derived from the four corner rooks.

In the starting position the rooks stand on the four corner squares (a1, h1,
a8, h8), which makes them the most reliable landmark for locating the board:
they are the outermost pieces, and their colour tells us which end is white's.

That gives both halves of calibration at once --

* **corners** -- the rook feet mark the centres of the corner squares, which sit
  half a square inside each board edge. Scaling those four points outward from
  their centroid by 8/7 recovers the board's outer corners.
* **orientation** -- whichever edge carries the *white* rooks is rank 1, so the
  rotation needed to bring rank 1 to the bottom of the warped image follows
  directly.

The maths here is deliberately pure Python so it can be unit-tested on a machine
with no OpenCV or camera attached.
"""

from __future__ import annotations

WHITE_ROOK = "white_rook"
BLACK_ROOK = "black_rook"

#: Corner-square centres span 7 squares; the board spans 8.
CORNER_EXPANSION = 8.0 / 7.0


class CalibrationError(RuntimeError):
    pass


def piece_base_point(detection: dict) -> tuple[float, float]:
    """Where a piece meets the board, in image pixels.

    A rook is tall, so the *centre* of its bounding box floats above the board
    plane and drifts further out the closer it is to the frame edge. The bottom
    edge of the box is the piece's foot, which is what actually sits on the
    square.
    """
    bbox = detection.get("bbox")
    if bbox and len(bbox) == 4:
        x1, _y1, x2, y2 = (float(v) for v in bbox)
        return ((x1 + x2) / 2.0, y2)
    center = detection.get("center")
    if center and len(center) == 2:
        return (float(center[0]), float(center[1]))
    raise CalibrationError("detection has neither bbox nor center")


def order_quad(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Order 4 points as top-left, top-right, bottom-right, bottom-left."""
    if len(points) != 4:
        raise CalibrationError(f"expected 4 points, got {len(points)}")
    by_sum = sorted(points, key=lambda p: p[0] + p[1])
    by_diff = sorted(points, key=lambda p: p[1] - p[0])
    top_left, bottom_right = by_sum[0], by_sum[-1]
    top_right, bottom_left = by_diff[0], by_diff[-1]
    ordered = [top_left, top_right, bottom_right, bottom_left]
    if len({(round(x, 3), round(y, 3)) for x, y in ordered}) != 4:
        raise CalibrationError("corner points are degenerate or collinear")
    return ordered


def expand_from_centroid(points: list[tuple[float, float]],
                         factor: float = CORNER_EXPANSION) -> list[tuple[float, float]]:
    """Scale points outward about their centroid."""
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    return [(cx + (x - cx) * factor, cy + (y - cy) * factor) for x, y in points]


def _pick_rooks(detections: list[dict]) -> tuple[list[dict], list[dict]]:
    """Highest-confidence two white rooks and two black rooks."""
    def top_two(name: str) -> list[dict]:
        matches = [d for d in detections if d.get("class_name") == name]
        matches.sort(key=lambda d: float(d.get("confidence", 0.0)), reverse=True)
        return matches[:2]

    return top_two(WHITE_ROOK), top_two(BLACK_ROOK)


def _white_edge(ordered: list[tuple[float, float]],
                white_points: list[tuple[float, float]]) -> str:
    """Which edge of the ordered quad carries the white rooks."""
    index_of = {}
    for point in white_points:
        # Match by identity of value; points came from this very list.
        for i, corner in enumerate(ordered):
            if corner == point:
                index_of[i] = True
                break
    indices = set(index_of)
    if indices == {2, 3}:
        return "bottom"
    if indices == {0, 1}:
        return "top"
    if indices == {0, 3}:
        return "left"
    if indices == {1, 2}:
        return "right"
    raise CalibrationError(
        "white rooks are not on a single edge; is the board in its start position?"
    )


#: Clockwise rotation to apply to the warped image so rank 1 ends at the bottom.
_EDGE_TO_ROTATION_CW = {"bottom": 0, "right": 90, "top": 180, "left": 270}


def calibrate_from_rooks(detections: list[dict]) -> dict:
    """Derive board corners and orientation from the four corner rooks.

    Returns a dict with ``corners`` (4 image points), ``rotation_cw`` (degrees to
    rotate the warped frame so rank 1 sits at the bottom), ``board_orientation``,
    and the confidence of the rooks used.
    """
    white, black = _pick_rooks(detections)
    if len(white) < 2 or len(black) < 2:
        raise CalibrationError(
            f"need 2 white and 2 black rooks, found {len(white)} white and "
            f"{len(black)} black -- set the board to its starting position"
        )

    white_points = [piece_base_point(d) for d in white]
    black_points = [piece_base_point(d) for d in black]
    ordered = order_quad(white_points + black_points)
    edge = _white_edge(ordered, white_points)

    corners = expand_from_centroid(ordered)
    confidences = [float(d.get("confidence", 0.0)) for d in white + black]
    return {
        "corners": [[round(x, 2), round(y, 2)] for x, y in corners],
        "rotation_cw": _EDGE_TO_ROTATION_CW[edge],
        "board_orientation": "white_bottom" if edge == "bottom" else "rotated",
        "white_edge": edge,
        "method": "corner_rooks",
        "min_confidence": round(min(confidences), 4),
    }


def rotate_warped(frame, rotation_cw: int):
    """Rotate a warped board image so rank 1 sits at the bottom.

    Kept next to the maths it undoes; imports OpenCV lazily so the rest of this
    module stays importable without it.
    """
    if not rotation_cw:
        return frame
    import cv2

    codes = {
        90: cv2.ROTATE_90_CLOCKWISE,
        180: cv2.ROTATE_180,
        270: cv2.ROTATE_90_COUNTERCLOCKWISE,
    }
    code = codes.get(int(rotation_cw) % 360)
    return frame if code is None else cv2.rotate(frame, code)
