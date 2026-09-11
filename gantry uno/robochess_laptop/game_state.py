"""
RoboChess - rules layer. Turns a requested move into a sequence of physical
gantry actions, and only advances the tracked board once they all succeed.

Uses python-chess for legality, disambiguation and special-move detection so
the gantry never tries to execute something illegal.
"""

import chess

import geometry as geo


class MoveRejected(ValueError):
    """The move is illegal or malformed - nothing moved physically."""


class PhysicalDesync(RuntimeError):
    """
    A gantry error happened part-way through a turn. Tracked state stays at
    the pre-move position, but the physical board may be half-moved. Surfaced
    loudly rather than silently drifting out of sync.
    """


class GameState:
    # home_mode after each move:
    #   "rehome" - drive into the limit switches and re-zero (default; immune
    #              to belt slip, costs a couple of seconds per move)
    #   "park"   - rapid to 0,0 by dead reckoning (fast, drifts over time)
    #   "none"   - stay where the move ended
    def __init__(self, gantry, home_mode="rehome"):
        self.gantry = gantry
        self.board = chess.Board()
        self.home_mode = home_mode
        self.graveyard = []          # list of piece symbols, index == slot index
        self.desynced = False
        self.desync_note = None

    # -- queries ------------------------------------------------------------
    def fen(self):
        return self.board.fen()

    def legal_targets(self, from_square_name):
        try:
            sq = chess.parse_square(from_square_name)
        except ValueError:
            return []
        return sorted({chess.square_name(m.to_square)
                       for m in self.board.legal_moves if m.from_square == sq})

    def status(self):
        b = self.board
        outcome = b.outcome(claim_draw=True)
        return {
            "fen": b.fen(),
            "turn": "white" if b.turn == chess.WHITE else "black",
            "check": b.is_check(),
            "game_over": outcome is not None,
            "result": outcome.result() if outcome else None,
            "termination": outcome.termination.name if outcome else None,
            "move_number": b.fullmove_number,
            "history": [m.uci() for m in b.move_stack],
            "san_history": self.san_history(),
            "graveyard": list(self.graveyard),
            "graveyard_used": len(self.graveyard),
            "graveyard_capacity": geo.GRAVEYARD_CAPACITY,
            "desynced": self.desynced,
            "desync_note": self.desync_note,
            "legal_moves": sorted({m.uci() for m in b.legal_moves}),
        }

    def san_history(self):
        replay = self.board.copy()
        while replay.move_stack:
            replay.pop()
        out = []
        for mv in self.board.move_stack:
            out.append(replay.san(mv))
            replay.push(mv)
        return out

    # -- move parsing -------------------------------------------------------
    def parse(self, text):
        """Accept SAN ('Nf6', 'exd5', 'O-O') or UCI ('g1f3', 'e7e8q')."""
        raw = (text or "").strip()
        if not raw:
            raise MoveRejected("empty move")
        try:
            return self.board.parse_san(raw)
        except ValueError:
            pass
        try:
            mv = chess.Move.from_uci(raw.lower())
        except ValueError:
            raise MoveRejected("could not read %r as SAN or UCI" % raw)
        if mv not in self.board.legal_moves:
            # A pawn reaching the last rank without a promotion suffix is the
            # common case here - make that error actionable.
            piece = self.board.piece_at(mv.from_square)
            if piece and piece.piece_type == chess.PAWN and mv.promotion is None \
                    and chess.square_rank(mv.to_square) in (0, 7):
                raise MoveRejected("promotion move needs a piece suffix, e.g. %sq" % raw)
            raise MoveRejected("illegal move: %s" % raw)
        return mv

    def move_from_squares(self, from_sq, to_sq, promotion=None):
        uci = "%s%s" % (from_sq.lower(), to_sq.lower())
        if promotion:
            uci += promotion.lower()[0]
        mv = chess.Move.from_uci(uci)
        if mv in self.board.legal_moves:
            return mv
        # Auto-queen if the caller omitted a needed promotion suffix.
        if mv.promotion is None:
            queened = chess.Move(mv.from_square, mv.to_square, promotion=chess.QUEEN)
            if queened in self.board.legal_moves:
                return queened
        raise MoveRejected("illegal move: %s -> %s" % (from_sq, to_sq))

    # -- physical execution -------------------------------------------------
    def plan(self, move):
        """
        Break a move into ordered physical actions. Each action is a dict the
        executor and the UI can both read.
        """
        b = self.board
        actions = []

        if b.is_en_passant(move):
            # The captured pawn is NOT on the destination square.
            cap_sq = chess.square(chess.square_file(move.to_square),
                                  chess.square_rank(move.from_square))
            actions.append({"kind": "park", "from": chess.square_name(cap_sq),
                            "why": "en passant capture"})
        elif b.is_capture(move):
            actions.append({"kind": "park", "from": chess.square_name(move.to_square),
                            "why": "capture"})

        actions.append({"kind": "move",
                        "from": chess.square_name(move.from_square),
                        "to": chess.square_name(move.to_square),
                        "why": "piece"})

        if b.is_castling(move):
            rank = chess.square_rank(move.from_square)
            if chess.square_file(move.to_square) > chess.square_file(move.from_square):
                rook_from, rook_to = chess.square(7, rank), chess.square(5, rank)   # h -> f
            else:
                rook_from, rook_to = chess.square(0, rank), chess.square(3, rank)   # a -> d
            actions.append({"kind": "move",
                            "from": chess.square_name(rook_from),
                            "to": chess.square_name(rook_to),
                            "why": "castling rook"})

        if move.promotion:
            actions.append({"kind": "note",
                            "why": "promotion to %s - swap the piece by hand, the gantry "
                                   "has no mechanism for this yet"
                                   % chess.piece_name(move.promotion)})
        return actions

    def execute(self, move):
        """
        Run a move physically, then advance tracked state. Raises
        PhysicalDesync if anything fails mid-sequence.
        """
        if self.desynced:
            raise PhysicalDesync(
                "board is flagged out of sync - fix the pieces and press Resync first")
        if move not in self.board.legal_moves:
            raise MoveRejected("illegal move: %s" % move.uci())

        san = self.board.san(move)
        actions = self.plan(move)
        done = []
        try:
            for act in actions:
                if act["kind"] == "park":
                    if len(self.graveyard) >= geo.GRAVEYARD_CAPACITY:
                        raise PhysicalDesync("parking strip is full (%d slots)"
                                             % geo.GRAVEYARD_CAPACITY)
                    slot = len(self.graveyard)
                    victim = self.board.piece_at(chess.parse_square(act["from"]))
                    self.gantry.log("park %s (%s) -> graveyard slot %d"
                                    % (act["from"], victim.symbol() if victim else "?", slot))
                    self.gantry.move_square_to_graveyard(act["from"], slot)
                    self.graveyard.append(victim.symbol() if victim else "?")
                    done.append(act)
                elif act["kind"] == "move":
                    self.gantry.log("drag %s -> %s (%s)" % (act["from"], act["to"], act["why"]))
                    self.gantry.move_square_to_square(act["from"], act["to"])
                    done.append(act)
                else:
                    self.gantry.log(act["why"], "warn")
        except Exception as exc:
            self.desynced = True
            self.desync_note = (
                "move %s failed after %d of %d physical action(s): %s. "
                "Tracked board is still at the position BEFORE this move; the "
                "physical board may be part-way through it."
                % (san, len(done), len([a for a in actions if a["kind"] != "note"]), exc))
            self.gantry.log(self.desync_note, "error")
            raise PhysicalDesync(self.desync_note)

        # Everything physical succeeded - now (and only now) advance state.
        self.board.push(move)

        # Re-datum against the limit switches after every move. A plain rapid
        # to 0,0 accumulates belt slip - each move lands slightly off and the
        # error compounds silently until pieces start missing their squares.
        # Touching the switches costs a couple of seconds and makes every move
        # start from a known-true zero instead of a drifting estimate.
        if self.home_mode == "rehome":
            try:
                self.gantry.cmd_home()
            except Exception as exc:
                self.gantry.log("re-home after move failed: %s" % exc, "warn")
        elif self.home_mode == "park":
            try:
                self.gantry.park()
            except Exception as exc:
                self.gantry.log("returned-home step failed: %s" % exc, "warn")
        return san

    # -- housekeeping -------------------------------------------------------
    def reset(self):
        self.board.reset()
        self.graveyard = []
        self.desynced = False
        self.desync_note = None

    def resync(self):
        """Operator has physically fixed the board to match tracked state."""
        self.desynced = False
        self.desync_note = None

    def undo_tracked(self):
        """Take back a move in software only - pieces are NOT moved back."""
        if not self.board.move_stack:
            raise MoveRejected("no moves to take back")
        mv = self.board.pop()
        return mv.uci()

    def set_fen(self, fen):
        try:
            self.board.set_fen(fen)
        except ValueError as exc:
            raise MoveRejected("bad FEN: %s" % exc)
        self.desynced = False
        self.desync_note = None
