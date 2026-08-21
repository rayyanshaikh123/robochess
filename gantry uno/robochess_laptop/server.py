"""
RoboChess - local web server. Run this on the laptop, open the browser UI,
drive the Uno over USB.

    python server.py            # then open http://127.0.0.1:8000
    python server.py --lan      # also reachable from your phone on the WiFi
"""

import argparse
import re
import webbrowser
import threading

from flask import Flask, jsonify, request, send_from_directory

import geometry as geo
import gantry as gantry_mod
from gantry import GantryController, GantryError
from game_state import GameState, MoveRejected, PhysicalDesync

app = Flask(__name__, static_folder="static", static_url_path="")

G = GantryController()
GAME = GameState(G)


def ok(**kw):
    d = {"ok": True}
    d.update(kw)
    return jsonify(d)


def fail(msg, code=400):
    G.log(str(msg), "error")
    return jsonify({"ok": False, "error": str(msg)}), code


# ---------------------------------------------------------------- static ---
@app.route("/")
def index():
    return send_from_directory("static", "index.html")


# ------------------------------------------------------------ connection ---
@app.route("/api/ports")
def api_ports():
    return ok(ports=gantry_mod.list_serial_ports())


@app.route("/api/connect", methods=["POST"])
def api_connect():
    data = request.get_json(force=True, silent=True) or {}
    port = data.get("port")
    simulate = bool(data.get("simulate"))
    if not port and not simulate:
        return fail("no port selected")
    try:
        G.connect(port or "SIM", int(data.get("baud") or gantry_mod.BAUD_DEFAULT),
                  simulate=simulate)
    except GantryError as exc:
        return fail(exc)
    return ok(state=G.state())


@app.route("/api/disconnect", methods=["POST"])
def api_disconnect():
    G.disconnect()
    return ok(state=G.state())


# ---------------------------------------------------------------- motion ---
@app.route("/api/home", methods=["POST"])
def api_home():
    try:
        G.clear_abort()
        G.submit("home", G.cmd_home)
    except GantryError as exc:
        return fail(exc)
    return ok()


@app.route("/api/park", methods=["POST"])
def api_park():
    try:
        G.submit("park", G.park)
    except GantryError as exc:
        return fail(exc)
    return ok()


@app.route("/api/stop", methods=["POST"])
def api_stop():
    G.cmd_stop()
    return ok(state=G.state())


@app.route("/api/clear-abort", methods=["POST"])
def api_clear_abort():
    G.clear_abort()
    return ok(state=G.state())


@app.route("/api/magnet", methods=["POST"])
def api_magnet():
    data = request.get_json(force=True, silent=True) or {}
    on = bool(data.get("on"))
    try:
        G.submit("magnet %s" % ("on" if on else "off"), lambda: G.cmd_magnet(on))
    except GantryError as exc:
        return fail(exc)
    return ok()


@app.route("/api/goto", methods=["POST"])
def api_goto():
    """The XY pad. Click anywhere -> gantry goes there."""
    data = request.get_json(force=True, silent=True) or {}
    try:
        x = float(data["x"])
        y = float(data["y"])
    except (KeyError, TypeError, ValueError):
        return fail("goto needs numeric x and y (mm)")
    if not geo.within_limits(x, y):
        return fail("(%.1f, %.1f) is outside the travel envelope 0..%.0f / 0..%.0f"
                    % (x, y, geo.MAX_X_MM, geo.MAX_Y_MM))
    magnet = data.get("magnet")

    def job():
        if magnet is not None:
            G.cmd_magnet(bool(magnet))
        G.cmd_movexy(x, y)

    try:
        G.submit("goto %.1f,%.1f" % (x, y), job)
    except GantryError as exc:
        return fail(exc)
    return ok()


@app.route("/api/setting", methods=["POST"])
def api_setting():
    """Push a firmware setting (SET <key> <value>) - saved to EEPROM there."""
    data = request.get_json(force=True, silent=True) or {}
    key = (data.get("key") or "").strip()
    val = str(data.get("value", "")).strip()
    if not key or not val:
        return fail("setting needs key and value")
    if not re.match(r"^[a-zA-Z0-9._]+$", key) or not re.match(r"^-?[\d.]+$", val):
        return fail("bad setting name or value")
    try:
        G.submit("set %s=%s" % (key, val),
                 lambda: G.send("SET %s %s" % (key, val), gantry_mod.TIMEOUT_SHORT_S))
    except GantryError as exc:
        return fail(exc)
    return ok()


@app.route("/api/raw", methods=["POST"])
def api_raw():
    data = request.get_json(force=True, silent=True) or {}
    line = (data.get("command") or "").strip()
    if not line:
        return fail("empty command")
    try:
        G.submit("raw %s" % line, lambda: G.send(line, gantry_mod.TIMEOUT_MOVE_S))
    except GantryError as exc:
        return fail(exc)
    return ok()


# ----------------------------------------------------------------- chess ---
@app.route("/api/game")
def api_game():
    return ok(game=GAME.status())


@app.route("/api/game/targets")
def api_targets():
    sq = request.args.get("from", "")
    return ok(targets=GAME.legal_targets(sq))


@app.route("/api/game/move", methods=["POST"])
def api_game_move():
    data = request.get_json(force=True, silent=True) or {}
    if G.busy or G.queued:
        return fail("gantry is still working on the previous move")
    try:
        if data.get("san"):
            move = GAME.parse(data["san"])
        elif data.get("from") and data.get("to"):
            move = GAME.move_from_squares(data["from"], data["to"], data.get("promotion"))
        else:
            return fail("send either {san} or {from,to}")
    except MoveRejected as exc:
        return fail(exc)

    if not G.connected:
        return fail("not connected to the gantry")

    preview = GAME.plan(move)
    san = GAME.board.san(move)

    def job():
        try:
            GAME.execute(move)
        except (MoveRejected, PhysicalDesync):
            pass  # already logged and flagged on GAME

    try:
        G.submit("move %s" % san, job)
    except GantryError as exc:
        return fail(exc)
    return ok(san=san, actions=preview)


@app.route("/api/game/preview", methods=["POST"])
def api_game_preview():
    """Dry run - what would move, without touching the gantry."""
    data = request.get_json(force=True, silent=True) or {}
    try:
        if data.get("san"):
            move = GAME.parse(data["san"])
        else:
            move = GAME.move_from_squares(data.get("from", ""), data.get("to", ""),
                                          data.get("promotion"))
    except MoveRejected as exc:
        return fail(exc)
    return ok(san=GAME.board.san(move), actions=GAME.plan(move))


@app.route("/api/game/reset", methods=["POST"])
def api_game_reset():
    GAME.reset()
    return ok(game=GAME.status())


@app.route("/api/game/resync", methods=["POST"])
def api_game_resync():
    GAME.resync()
    return ok(game=GAME.status())


@app.route("/api/game/undo", methods=["POST"])
def api_game_undo():
    try:
        uci = GAME.undo_tracked()
    except MoveRejected as exc:
        return fail(exc)
    return ok(undone=uci, game=GAME.status())


# Display-only mirroring. Which way the board "reads" depends on which side
# of the machine you sit; the gantry is already moving correctly, so this
# must never touch the coordinates sent to the firmware - only how the pad
# and the chessboard are drawn, and how a click maps back to a square.
VIEW = {"flip_x": False, "flip_y": False}


@app.route("/api/view", methods=["POST"])
def api_view():
    data = request.get_json(force=True, silent=True) or {}
    for k in ("flip_x", "flip_y"):
        if k in data:
            VIEW[k] = bool(data[k])
    return ok(view=dict(VIEW))


@app.route("/api/game/options", methods=["POST"])
def api_game_options():
    data = request.get_json(force=True, silent=True) or {}
    if "home_mode" in data:
        mode = str(data["home_mode"]).lower()
        if mode not in ("rehome", "park", "none"):
            return fail("home_mode must be rehome, park or none")
        GAME.home_mode = mode
    return ok(home_mode=GAME.home_mode)


# ----------------------------------------------------------------- state ---
@app.route("/api/state")
def api_state():
    since = int(request.args.get("since", 0) or 0)
    return ok(state=G.state(),
              game=GAME.status(),
              home_mode=GAME.home_mode,
              view=dict(VIEW),
              log=G.log_since(since))


@app.route("/api/geometry")
def api_geometry():
    squares = {}
    for f in "abcdefgh":
        for r in "12345678":
            x, y = geo.square_to_mm(f + r)
            squares[f + r] = [round(x, 2), round(y, 2)]
    return ok(geometry={
        "max_x": geo.MAX_X_MM,
        "max_y": geo.MAX_Y_MM,
        "origin_x": geo.ORIGIN_OFFSET_X_MM,
        "origin_y": geo.ORIGIN_OFFSET_Y_MM,
        "square": geo.SQUARE_SIZE_MM,
        "board_span": geo.BOARD_SPAN_MM,
        "graveyard_x": geo.GRAVEYARD_X_START_MM,
        "graveyard_depth": geo.GRAVEYARD_DEPTH_MM,
        "graveyard_rows": geo.GRAVEYARD_ROWS,
        "graveyard_cols": geo.GRAVEYARD_COLS,
        "slots": [[round(v, 2) for v in geo.graveyard_slot_mm(i)]
                  for i in range(geo.GRAVEYARD_CAPACITY)],
        "squares": squares,
        "files_reversed": geo.FILES_REVERSED,
        "ranks_reversed": geo.RANKS_REVERSED,
        "describe": geo.describe(),
    })


def main():
    ap = argparse.ArgumentParser(description="RoboChess laptop control server")
    ap.add_argument("--host", default=None)
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--lan", action="store_true",
                    help="listen on all interfaces so a phone on the same WiFi can connect")
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()

    host = args.host or ("0.0.0.0" if args.lan else "127.0.0.1")
    url = "http://127.0.0.1:%d" % args.port
    print("RoboChess control server -> %s" % url)
    print(geo.describe())
    if args.lan:
        print("LAN mode: also reachable at http://<your-laptop-ip>:%d" % args.port)
    if not args.no_browser:
        threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    app.run(host=host, port=args.port, threaded=True, debug=False)


if __name__ == "__main__":
    main()
