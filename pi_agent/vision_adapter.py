from typing import Iterable, Optional, Tuple

from pi_agent.game_session import GameSession, SessionError


class VisionAdapter:
    """Camera integration seam.

    A detector should call ``observe_candidates`` with its stable UCI candidates.
    Only a candidate seen ``stability_frames`` times and legal for the session is
    emitted; camera capture/model code deliberately remains outside the agent.
    """
    def __init__(self, session: GameSession | None = None, stability_frames: int = 3) -> None:
        self.session = session
        self.stability_frames = max(1, stability_frames)
        self._candidate: str | None = None
        self._count = 0

    def detect_move(self) -> Tuple[Optional[str], Optional[int]]:
        # The OpenCV/model producer calls observe_candidates when a frame is ready.
        return None, None

    def observe_candidates(self, candidates: Iterable[str]) -> Tuple[Optional[str], Optional[int]]:
        if not self.session:
            return None, None
        legal = []
        for candidate in candidates:
            try:
                legal.append(self.session.parse_legal_move(candidate).uci())
            except SessionError:
                continue
        choice = legal[0] if len(legal) == 1 else None
        if choice != self._candidate:
            self._candidate, self._count = choice, 1 if choice else 0
            return None, None
        self._count += 1
        if choice and self._count >= self.stability_frames:
            self._candidate, self._count = None, 0
            return choice, self.session.version
        return None, None
