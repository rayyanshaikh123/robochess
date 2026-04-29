"""Production-style Tkinter dashboard for RoboChess.

The app is organized as a clear operator workflow:
1. Load the model, Stockfish, and camera.
2. Calibrate the board by clicking four corners.
3. Watch the live board and wait for a stable human move.
4. Trigger Stockfish manually for the engine reply.

The UI keeps the live video, game state, and setup controls visible at the same time so it is easier to use than the previous tabbed layout.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import chess
import chess.engine
import cv2
import numpy as np
import tkinter as tk
from PIL import Image, ImageTk
from tkinter import filedialog, messagebox, ttk

# Reduce OpenCV threading to avoid sporadic GUI crashes on macOS.
try:
    cv2.setNumThreads(1)
    cv2.ocl.setUseOpenCL(False)
except Exception:
    pass

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

try:
    from backend.board_recognizer import BoardRecognizer
except ImportError:
    from board_recognizer import BoardRecognizer


ROOT = Path(__file__).parent.resolve()
if load_dotenv:
    load_dotenv(ROOT / ".env")

def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


DEFAULT_MODEL_PATH = ROOT / "models" / "best.pt"
DEFAULT_STOCKFISH_PATH = ROOT / "stockfish" / "stockfish-windows-x86-64-avx2.exe"
DEFAULT_CONFIG_PATH = ROOT / "robochess_ui.json"
PREVIEW_WIDTH = 420
PREVIEW_HEIGHT = 520
CAPTURE_WIDTH = 820
CAPTURE_HEIGHT = 620
BOARD_DISPLAY_SIZE = 896
DETECTION_CONFIDENCE_MIN = _env_float("ROBOCHESS_DET_CONF", 0.45)
MOVE_MATCH_MIN_SCORE = 54
MOVE_MATCH_MIN_GAP = 2
START_MAX_MISSING = _env_int("ROBOCHESS_START_MISSING", 4)
START_MAX_EXTRA = _env_int("ROBOCHESS_START_EXTRA", 2)
CAPTURE_DELAY_SEC = _env_float("ROBOCHESS_CAPTURE_DELAY", 0.25)
RECAPTURE_DELAY_SEC = _env_float("ROBOCHESS_RECAPTURE_DELAY", 0.4)
HAND_ABSENCE_SECONDS = _env_float("ROBOCHESS_HAND_ABSENCE", 0.35)
HAND_TRIGGER_COOLDOWN = _env_float("ROBOCHESS_HAND_COOLDOWN", 0.8)
MOTION_DIFF_THRESHOLD = _env_int("ROBOCHESS_MOTION_DIFF", 20)
MOTION_RATIO_TRIGGER = _env_float("ROBOCHESS_MOTION_RATIO", 0.02)
MOTION_BLUR = _env_int("ROBOCHESS_MOTION_BLUR", 7)
ENGINE_AUTO_DELAY_SEC = 0.15
ASSUME_STANDARD_START = bool(_env_int("ROBOCHESS_ASSUME_START", 1))
AUTO_ENGINE_REPLY = bool(_env_int("ROBOCHESS_AUTO_ENGINE", 1))
CAPTURE_SAMPLES = _env_int("ROBOCHESS_CAPTURE_SAMPLES", 2)
CAPTURE_SAMPLE_DELAY = _env_float("ROBOCHESS_CAPTURE_SAMPLE_DELAY", 0.05)
STABLE_LABEL_MIN_COUNT = _env_int("ROBOCHESS_STABLE_LABEL_COUNT", 2)
OCCUPANCY_ONLY = bool(_env_int("ROBOCHESS_OCCUPANCY_ONLY", 1))


@dataclass
class AppConfig:
    model_path: str = str(DEFAULT_MODEL_PATH)
    stockfish_path: str = str(DEFAULT_STOCKFISH_PATH)
    camera_index: int = 0
    confidence: float = _env_float("ROBOCHESS_CONFIDENCE", 0.10)
    engine_time: float = 0.50
    stability_frames: int = 5
    human_side: str = "white"
    calibration_points: list[list[float]] = field(default_factory=list)

    @classmethod
    def load(cls, path: Path) -> "AppConfig":
        if not path.exists():
            return cls()
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            return cls(
                model_path=str(payload.get("model_path", str(DEFAULT_MODEL_PATH))),
                stockfish_path=str(payload.get("stockfish_path", str(DEFAULT_STOCKFISH_PATH))),
                camera_index=int(payload.get("camera_index", 0)),
                confidence=float(payload.get("confidence", 0.10)),
                engine_time=float(payload.get("engine_time", 0.50)),
                stability_frames=int(payload.get("stability_frames", 5)),
                human_side=str(payload.get("human_side", "white")),
                calibration_points=[list(point) for point in payload.get("calibration_points", [])],
            )
        except Exception:
            return cls()

    def save(self, path: Path) -> None:
        path.write_text(
            json.dumps(
                {
                    "model_path": self.model_path,
                    "stockfish_path": self.stockfish_path,
                    "camera_index": int(self.camera_index),
                    "confidence": float(self.confidence),
                    "engine_time": float(self.engine_time),
                    "stability_frames": int(self.stability_frames),
                    "human_side": self.human_side,
                    "calibration_points": self.calibration_points,
                },
                indent=2,
            ),
            encoding="utf-8",
        )


def resolve_stockfish(path: str) -> Optional[str]:
    if not path:
        return None
    resolved = Path(path).expanduser()
    if resolved.is_file():
        return str(resolved)
    return shutil.which(path)


def open_camera(camera_index: int) -> Optional[cv2.VideoCapture]:
    backends = [cv2.CAP_ANY]
    if os.name == "nt":
        backends = [cv2.CAP_DSHOW, cv2.CAP_MSMF, cv2.CAP_ANY]

    for backend in backends:
        capture = cv2.VideoCapture(camera_index, backend)
        if capture.isOpened():
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)
            capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            return capture
        capture.release()
    return None


def is_cloud_model_reference(model_ref: str) -> bool:
    text = str(model_ref).strip()
    if not text:
        return False
    if text.lower().startswith("rf://"):
        return True
    return "/" in text and "\\" not in text and ":" not in text and not text.lower().endswith(".pt")


class RoboChessControlCenter(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("RoboChess Control Center")
        self.geometry("1420x880")
        self.minsize(1280, 820)
        self.configure(bg="#101418")

        self.config_path = DEFAULT_CONFIG_PATH
        self.app_config = AppConfig.load(self.config_path)

        self.state_lock = threading.RLock()
        self.stop_event = threading.Event()
        self.is_paused = False

        self.recognizer: Optional[BoardRecognizer] = None
        self.engine: Optional[chess.engine.SimpleEngine] = None
        self.capture: Optional[cv2.VideoCapture] = None
        self.camera_thread: Optional[threading.Thread] = None
        self.analysis_thread: Optional[threading.Thread] = None
        self.hand_thread: Optional[threading.Thread] = None
        self.tracking_thread: Optional[threading.Thread] = None

        self.board = chess.Board()
        self.move_history: list[dict] = []
        self.phase = "idle"
        self.calibration_mode = False
        self.calibration_points: list[tuple[float, float]] = [
            (float(point[0]), float(point[1])) for point in self.app_config.calibration_points
        ]
        self.prev_board_fen: Optional[str] = None
        self.candidate_fen: Optional[str] = None
        self.candidate_move: Optional[chess.Move] = None
        self.candidate_move_streak = 0
        self.candidate_miss_count = 0
        self.move_confirm_frames = 1
        self.stable_count = 0
        self.latest_frame: Optional[np.ndarray] = None
        self.latest_display_frame: Optional[np.ndarray] = None
        self.latest_vision_fen: Optional[str] = None
        self.latest_detection_count = 0
        self.prev_board_overlay: Optional[np.ndarray] = None
        self.cached_board_view: Optional[np.ndarray] = None
        self.cached_curr_fen: Optional[str] = None
        self.cached_detection_count = 0
        self.next_snapshot_at = 0.0
        self.display_image = None
        self.last_camera_rect: tuple[int, int, int, int] = (0, 0, PREVIEW_WIDTH, PREVIEW_HEIGHT)
        self.preview_width = PREVIEW_WIDTH
        self.preview_height = PREVIEW_HEIGHT

        self.initial_board_validated = False
        self.last_detection_state: Optional[dict[str, Optional[str]]] = None
        self.last_detection_board_view: Optional[np.ndarray] = None
        self.last_detection_reason = ""
        self.last_detection_score = 0
        self.last_detection_second_score = 0
        self.last_changed_squares: list[str] = []
        self.last_invalid_squares: list[str] = []
        self.capture_in_flight = False
        self.last_trigger_time = 0.0
        self.last_recapture_time = 0.0
        self.hand_present = False
        self.hand_last_seen = 0.0
        self.tracked_state: Optional[dict[str, Optional[str]]] = None
        self.tracked_points: list[dict] = []
        self.tracking_prev_gray: Optional[np.ndarray] = None

        self.status_message = "Load the model, camera, and Stockfish to begin."

        self.canvas_click_hint = tk.StringVar(value="Click Calibrate Corners, then mark TL, TR, BR, BL on the live board.")
        self.connection_status_var = tk.StringVar(value="Model: not loaded | Camera: closed | Engine: not loaded")
        self.step_status_var = tk.StringVar(value="Step 1/4: Setup")
        self.status_var = tk.StringVar(value=self.status_message)
        self.init_status_var = tk.StringVar(value="Not initialized")
        self.board_fen_var = tk.StringVar(value="FEN: -")
        self.turn_var = tk.StringVar(value="Turn: -")
        self.phase_var = tk.StringVar(value="Phase: idle")
        self.calibration_status_var = tk.StringVar(value="Calibration: pending")
        self.engine_status_var = tk.StringVar(value="Engine: idle")
        self.fen_var = tk.StringVar(value="FEN: -")
        self.vision_var = tk.StringVar(value="Vision: -")
        self.move_time_var = tk.StringVar(value="Last human move time: -")

        self._build_styles()
        self._build_menu()
        self._build_layout()
        self._load_config_into_ui()
        self._refresh_ui_state()

        self.bind("<space>", self.trigger_manual_capture)

        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.after(40, self._refresh_ui)

    # ------------------------------------------------------------------
    # UI
    # ------------------------------------------------------------------

    def _build_styles(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except Exception:
            pass

        style.configure("App.TFrame", background="#101418")
        style.configure("Panel.TFrame", background="#161b22")
        style.configure("Footer.TFrame", background="#0d1117")
        style.configure("Title.TLabel", background="#101418", foreground="#f0f6fc", font=("Segoe UI", 20, "bold"))
        style.configure("Subtitle.TLabel", background="#101418", foreground="#9da7b3", font=("Segoe UI", 10))
        style.configure("Badge.TLabel", background="#243041", foreground="#c9d1d9", font=("Segoe UI", 9, "bold"), padding=(10, 5))
        style.configure("StatusLine.TLabel", background="#101418", foreground="#7ee787", font=("Segoe UI", 10, "bold"))
        style.configure("Section.TLabelframe", background="#161b22", foreground="#f0f6fc")
        style.configure("Section.TLabelframe.Label", background="#161b22", foreground="#f0f6fc", font=("Segoe UI", 10, "bold"))
        style.configure("Panel.TLabel", background="#161b22", foreground="#c9d1d9", font=("Segoe UI", 10))
        style.configure("Muted.TLabel", background="#161b22", foreground="#8b949e", font=("Segoe UI", 9))
        style.configure("Footer.TLabel", background="#0d1117", foreground="#c9d1d9", font=("Segoe UI", 9))
        style.configure("Action.TButton", padding=(12, 8), font=("Segoe UI", 10, "bold"))
        style.configure("Small.TButton", padding=(8, 5), font=("Segoe UI", 9, "bold"))

    def _build_menu(self) -> None:
        menubar = tk.Menu(self)

        file_menu = tk.Menu(menubar, tearoff=0)
        file_menu.add_command(label="Initialize", command=self.initialize_system)
        file_menu.add_command(label="New Game", command=self.new_game)
        file_menu.add_command(label="Save Settings", command=self.save_settings)
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self.on_close)
        menubar.add_cascade(label="File", menu=file_menu)

        view_menu = tk.Menu(menubar, tearoff=0)
        view_menu.add_command(label="Pause/Resume", command=self.toggle_pause)
        view_menu.add_command(label="Clear Calibration", command=self.clear_calibration)
        menubar.add_cascade(label="View", menu=view_menu)

        help_menu = tk.Menu(menubar, tearoff=0)
        help_menu.add_command(label="How to use", command=self.show_help)
        help_menu.add_command(label="About", command=self.show_about)
        menubar.add_cascade(label="Help", menu=help_menu)

        self.config(menu=menubar)

    def _build_layout(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        header = ttk.Frame(self, padding=(18, 14, 18, 10), style="App.TFrame")
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=1)

        title_row = ttk.Frame(header, style="App.TFrame")
        title_row.grid(row=0, column=0, sticky="ew")
        title_row.columnconfigure(0, weight=1)
        ttk.Label(title_row, text="RoboChess Control Center", style="Title.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(title_row, textvariable=self.step_status_var, style="Badge.TLabel").grid(row=0, column=1, sticky="e")

        ttk.Label(
            header,
            text="A clear desktop workflow for camera setup, board calibration, move recognition, and Stockfish replies.",
            style="Subtitle.TLabel",
            wraplength=1240,
            justify="left",
        ).grid(row=1, column=0, sticky="w", pady=(6, 0))

        ttk.Label(header, textvariable=self.connection_status_var, style="StatusLine.TLabel", wraplength=1240, justify="left").grid(
            row=2, column=0, sticky="w", pady=(8, 0)
        )

        body = ttk.Panedwindow(self, orient=tk.HORIZONTAL)
        body.grid(row=1, column=0, sticky="nsew")

        left_panel = ttk.Frame(body, padding=14, style="Panel.TFrame")
        center_panel = ttk.Frame(body, padding=14, style="Panel.TFrame")
        right_panel = ttk.Frame(body, padding=14, style="Panel.TFrame")
        body.add(left_panel, weight=1)
        body.add(center_panel, weight=3)
        body.add(right_panel, weight=1)

        self._build_setup_panel(left_panel)
        self._build_live_panel(center_panel)
        self._build_game_panel(right_panel)

        footer = ttk.Frame(self, padding=(18, 8, 18, 12), style="Footer.TFrame")
        footer.grid(row=2, column=0, sticky="ew")
        footer.columnconfigure(0, weight=1)
        ttk.Label(footer, textvariable=self.status_var, style="Footer.TLabel", wraplength=1280, justify="left").grid(row=0, column=0, sticky="w")

    def _build_setup_panel(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)

        ttk.Label(parent, text="Workflow", style="Panel.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(
            parent,
            text="1. Load model and engine\n2. Start camera\n3. Calibrate corners\n4. Make a move\n5. Ask Stockfish",
            style="Muted.TLabel",
            justify="left",
        ).grid(row=1, column=0, sticky="w", pady=(4, 12))

        setup_card = self._section(parent, "Setup", 2)
        self.model_path_var = tk.StringVar()
        self.stockfish_path_var = tk.StringVar()
        self.camera_index_var = tk.IntVar()
        self.confidence_var = tk.DoubleVar()
        self.engine_time_var = tk.DoubleVar()
        self.stability_frames_var = tk.IntVar()
        self.human_side_var = tk.StringVar()

        self._field(setup_card, 0, "Model path", self.model_path_var, self.browse_model)
        self._field(setup_card, 2, "Stockfish path", self.stockfish_path_var, self.browse_stockfish)
        self._spinfield(setup_card, 4, "Camera index", self.camera_index_var, 0, 10)
        self._choicefield(setup_card, 6, "Your side", self.human_side_var, ["white", "black"])
        self._sliderfield(setup_card, 8, "Detection confidence", self.confidence_var, 0.01, 0.95)
        self._sliderfield(setup_card, 10, "Engine think time", self.engine_time_var, 0.10, 5.00)
        self._spinfield(setup_card, 12, "Stable frames", self.stability_frames_var, 1, 20)

        button_row = ttk.Frame(setup_card, style="Panel.TFrame")
        button_row.grid(row=16, column=0, sticky="ew", pady=(12, 0))
        button_row.columnconfigure(0, weight=1)
        button_row.columnconfigure(1, weight=1)
        button_row.columnconfigure(2, weight=1)
        ttk.Button(button_row, text="Save", style="Action.TButton", command=self.save_settings).grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(button_row, text="Init", style="Action.TButton", command=self.initialize_system).grid(row=0, column=1, sticky="ew", padx=6)
        ttk.Button(button_row, text="Reload", style="Action.TButton", command=self.load_settings).grid(row=0, column=2, sticky="ew", padx=(6, 0))

        self.init_status_var = tk.StringVar(value="Not initialized")
        ttk.Label(setup_card, textvariable=self.init_status_var, style="Muted.TLabel", wraplength=360, justify="left").grid(row=14, column=0, sticky="ew", pady=(10, 0))

    def _build_live_panel(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.rowconfigure(1, weight=1)

        ttk.Label(parent, text="Live board", style="Panel.TLabel").grid(row=0, column=0, sticky="w")
        self.canvas = tk.Canvas(parent, width=PREVIEW_WIDTH, height=PREVIEW_HEIGHT, bg="#000000", highlightthickness=0, bd=0)
        self.canvas.grid(row=1, column=0, sticky="nsew", pady=(8, 10))
        self.canvas.bind("<Button-1>", self.on_canvas_click)
        self.canvas.bind("<Configure>", self._on_canvas_resize)
        ttk.Label(parent, textvariable=self.canvas_click_hint, style="Muted.TLabel").grid(row=2, column=0, sticky="w")

        self.fen_var = tk.StringVar(value="FEN: -")
        self.vision_var = tk.StringVar(value="Vision: -")
        ttk.Label(parent, textvariable=self.fen_var, style="Panel.TLabel", wraplength=760, justify="left").grid(row=3, column=0, sticky="ew", pady=(10, 2))
        ttk.Label(parent, textvariable=self.vision_var, style="Muted.TLabel", wraplength=760, justify="left").grid(row=4, column=0, sticky="ew")

        controls = ttk.Frame(parent, style="Panel.TFrame")
        controls.grid(row=5, column=0, sticky="ew", pady=(12, 0))
        for index in range(7):
            controls.columnconfigure(index, weight=1)

        ttk.Button(controls, text="Calibrate", style="Small.TButton", command=self.begin_calibration).grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(controls, text="Clear", style="Small.TButton", command=self.clear_calibration).grid(row=0, column=1, sticky="ew", padx=6)
        ttk.Button(controls, text="Capture", style="Small.TButton", command=self.trigger_manual_capture).grid(row=0, column=2, sticky="ew", padx=6)
        self.validate_button = ttk.Button(
            controls,
            text="Validate start",
            style="Small.TButton",
            command=self.validate_starting_position,
        )
        self.validate_button.grid(row=0, column=3, sticky="ew", padx=6)
        ttk.Button(controls, text="Pause", style="Small.TButton", command=self.toggle_pause).grid(row=0, column=4, sticky="ew", padx=6)
        ttk.Button(controls, text="New game", style="Small.TButton", command=self.new_game).grid(row=0, column=5, sticky="ew", padx=6)
        ttk.Button(controls, text="Engine reply", style="Small.TButton", command=self.apply_engine_move).grid(row=0, column=6, sticky="ew", padx=(6, 0))

    def _build_game_panel(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.rowconfigure(7, weight=1)

        state_card = self._section(parent, "Game state", 0)
        ttk.Label(state_card, textvariable=self.board_fen_var, style="Muted.TLabel", wraplength=340, justify="left").grid(row=0, column=0, sticky="ew", pady=(6, 2))
        ttk.Label(state_card, textvariable=self.turn_var, style="Panel.TLabel").grid(row=1, column=0, sticky="w")
        ttk.Label(state_card, textvariable=self.phase_var, style="Panel.TLabel").grid(row=2, column=0, sticky="w")
        ttk.Label(state_card, textvariable=self.calibration_status_var, style="Panel.TLabel").grid(row=3, column=0, sticky="w")
        ttk.Label(state_card, textvariable=self.engine_status_var, style="Panel.TLabel").grid(row=4, column=0, sticky="w")
        ttk.Label(state_card, textvariable=self.move_time_var, style="Panel.TLabel").grid(row=5, column=0, sticky="w", pady=(6, 0))
        ttk.Button(state_card, text="Mark move time", style="Small.TButton", command=self.mark_move_time).grid(
            row=6, column=0, sticky="ew", pady=(8, 0)
        )

        moves_card = self._section(parent, "Moves", 6)
        history_frame = ttk.Frame(moves_card, style="Panel.TFrame")
        history_frame.grid(row=0, column=0, sticky="nsew", pady=(6, 0))
        history_frame.columnconfigure(0, weight=1)
        history_frame.rowconfigure(0, weight=1)
        self.history_listbox = tk.Listbox(
            history_frame,
            height=18,
            font=("Consolas", 10),
            bg="#0d1117",
            fg="#c9d1d9",
            highlightthickness=0,
            bd=0,
            selectbackground="#30363d",
        )
        self.history_listbox.grid(row=0, column=0, sticky="nsew")
        history_scroll = ttk.Scrollbar(history_frame, orient="vertical", command=self.history_listbox.yview)
        history_scroll.grid(row=0, column=1, sticky="ns")
        self.history_listbox.configure(yscrollcommand=history_scroll.set)

        manual_frame = self._section(parent, "Manual move", 8)
        manual_frame.grid_configure(pady=(12, 0))
        manual_frame.columnconfigure(0, weight=1)
        self.manual_move_var = tk.StringVar()
        ttk.Label(manual_frame, text="Manual UCI move", style="Panel.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Entry(manual_frame, textvariable=self.manual_move_var).grid(row=1, column=0, sticky="ew", pady=(6, 8))
        ttk.Button(manual_frame, text="Play manual move", style="Small.TButton", command=self.play_manual_move).grid(row=2, column=0, sticky="ew")

    def _section(self, parent: ttk.Frame, title: str, row: int) -> ttk.LabelFrame:
        frame = ttk.LabelFrame(parent, text=title, style="Section.TLabelframe", padding=10)
        frame.grid(row=row, column=0, sticky="ew", pady=(0, 10))
        frame.columnconfigure(0, weight=1)
        return frame

    def _field(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar, browse_command) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", pady=(0, 2))
        field = ttk.Frame(parent, style="Panel.TFrame")
        field.grid(row=row + 1, column=0, sticky="ew", pady=(0, 10))
        field.columnconfigure(0, weight=1)
        ttk.Entry(field, textvariable=variable).grid(row=0, column=0, sticky="ew")
        ttk.Button(field, text="Browse", command=browse_command).grid(row=0, column=1, padx=(8, 0))

    def _spinfield(self, parent: ttk.Frame, row: int, label: str, variable: tk.Variable, minimum: int, maximum: int) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", pady=(0, 2))
        ttk.Spinbox(parent, textvariable=variable, from_=minimum, to=maximum, width=12).grid(row=row + 1, column=0, sticky="w", pady=(0, 10))

    def _sliderfield(self, parent: ttk.Frame, row: int, label: str, variable: tk.Variable, minimum: float, maximum: float) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", pady=(0, 2))
        slider_row = ttk.Frame(parent, style="Panel.TFrame")
        slider_row.grid(row=row + 1, column=0, sticky="ew", pady=(0, 10))
        slider_row.columnconfigure(0, weight=1)
        scale = ttk.Scale(slider_row, variable=variable, from_=minimum, to=maximum, orient="horizontal")
        scale.grid(row=0, column=0, sticky="ew")
        ttk.Label(slider_row, textvariable=variable, style="Muted.TLabel", width=8).grid(row=0, column=1, padx=(8, 0))

    def _choicefield(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar, values: list[str]) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", pady=(0, 2))
        combo = ttk.Combobox(parent, textvariable=variable, values=values, state="readonly", width=14)
        combo.grid(row=row + 1, column=0, sticky="w", pady=(0, 10))

    def browse_model(self) -> None:
        path = filedialog.askopenfilename(
            title="Select model checkpoint",
            initialdir=str(ROOT),
            filetypes=[("PyTorch model", "*.pt"), ("All files", "*.*")],
        )
        if path:
            self.model_path_var.set(path)
            self._set_status("Model path updated.")

    def browse_stockfish(self) -> None:
        path = filedialog.askopenfilename(
            title="Select Stockfish executable",
            initialdir=str(ROOT),
            filetypes=[("Windows executable", "*.exe"), ("All files", "*.*")],
        )
        if path:
            self.stockfish_path_var.set(path)
            self._set_status("Stockfish path updated.")

    # ------------------------------------------------------------------
    # Config + boot
    # ------------------------------------------------------------------

    def _load_config_into_ui(self) -> None:
        self.model_path_var.set(self.app_config.model_path)
        self.stockfish_path_var.set(self.app_config.stockfish_path)
        self.camera_index_var.set(self.app_config.camera_index)
        self.confidence_var.set(round(float(self.app_config.confidence), 2))
        self.engine_time_var.set(round(float(self.app_config.engine_time), 2))
        self.stability_frames_var.set(int(self.app_config.stability_frames))
        self.human_side_var.set(str(self.app_config.human_side).strip().lower() or "white")
        self._refresh_connection_text()

    def _sync_config_from_ui(self) -> None:
        self.app_config.model_path = self.model_path_var.get().strip()
        self.app_config.stockfish_path = self.stockfish_path_var.get().strip()
        self.app_config.camera_index = int(self.camera_index_var.get())
        self.app_config.confidence = float(self.confidence_var.get())
        self.app_config.engine_time = float(self.engine_time_var.get())
        self.app_config.stability_frames = max(1, int(self.stability_frames_var.get()))
        selected_side = str(self.human_side_var.get()).strip().lower()
        self.app_config.human_side = "black" if selected_side == "black" else "white"
        self.app_config.calibration_points = [[float(x), float(y)] for x, y in self.calibration_points]

    def _human_color(self) -> chess.Color:
        return chess.BLACK if str(self.app_config.human_side).strip().lower() == "black" else chess.WHITE

    def _engine_color(self) -> chess.Color:
        return chess.WHITE if self._human_color() == chess.BLACK else chess.BLACK

    def _refresh_connection_text(self) -> None:
        model_state = "loaded" if self.recognizer and self.recognizer.is_ready else "not loaded"
        camera_state = "open" if self.capture is not None else "closed"
        engine_state = "loaded" if self.engine is not None else "not loaded"
        self.connection_status_var.set(f"Model: {model_state} | Camera: {camera_state} | Engine: {engine_state}")
        if hasattr(self, "validate_button"):
            button_state = "disabled" if ASSUME_STANDARD_START else "normal"
            self.validate_button.configure(state=button_state)

    def load_settings(self) -> None:
        self.app_config = AppConfig.load(self.config_path)
        self.calibration_points = [(float(point[0]), float(point[1])) for point in self.app_config.calibration_points]
        self._load_config_into_ui()
        self._set_status("Settings loaded from disk.")

    def save_settings(self) -> None:
        try:
            self._sync_config_from_ui()
            self.app_config.save(self.config_path)
            self._set_status(f"Settings saved to {self.config_path.name}.")
        except Exception as exc:
            messagebox.showerror("Save failed", str(exc))

    def initialize_system(self) -> None:
        self._sync_config_from_ui()
        self.save_settings()

        self.initial_board_validated = False
        self.last_detection_state = None
        self.last_detection_board_view = None
        self.last_detection_reason = ""
        self.last_detection_score = 0
        self.last_detection_second_score = 0
        self.last_changed_squares = []
        self.last_invalid_squares = []
        self.latest_vision_fen = None
        self.latest_detection_count = 0

        self._load_model()
        self._load_engine()
        self._open_camera()
        self._start_workers()

        if self.recognizer and self.recognizer.is_calibrated:
            if ASSUME_STANDARD_START:
                self.board = chess.Board()
                self.prev_board_fen = self.board.board_fen()
                self.initial_board_validated = True
                self.phase = "waiting_human" if self.board.turn == self._human_color() else "awaiting_engine"
                self.status_message = "Calibration loaded. Waiting for the first move."
            else:
                self.phase = "idle"
                self.prev_board_fen = None
                self.status_message = "Board calibration loaded. Click Validate start to confirm the starting position."
        elif self.recognizer:
            self.phase = "calibrating"
            self.status_message = "Model ready. Click Calibrate to begin board corner selection."
        elif self.capture is not None:
            self.phase = "idle"
            self.status_message = "Camera is ready. Load a model to enable recognition."

        self.step_status_var.set(self._step_label())
        self._set_status(self.status_message)
        self._refresh_connection_text()

    def _step_label(self) -> str:
        if self.phase == "calibrating":
            return "Step 2/4: Calibrate"
        if self.recognizer and self.recognizer.is_calibrated and not self.initial_board_validated:
            return "Step 2/4: Validate start"
        if self.phase == "sync_board":
            return "Step 3/4: Human move"
        if self.phase == "awaiting_engine":
            return "Step 4/4: Engine reply"
        if self.phase == "waiting_human":
            return "Step 3/4: Human move"
        if self.phase == "idle":
            return "Step 1/4: Setup"
        return "Step 1/4: Setup"

    def _load_model(self) -> None:
        model_ref = self.app_config.model_path.strip()
        if not is_cloud_model_reference(model_ref) and not Path(model_ref).exists():
            self.recognizer = None
            self.init_status_var.set(f"Model not found: {self.app_config.model_path}")
            return

        try:
            self.recognizer = BoardRecognizer(self.app_config.model_path, confidence=float(self.app_config.confidence))
            self.recognizer.confidence = float(self.app_config.confidence)
            self.recognizer.BOARD_SIZE = BOARD_DISPLAY_SIZE
            if self.calibration_points:
                try:
                    self.recognizer.calibrate(self.calibration_points)
                except Exception:
                    self.recognizer.warp_matrix = None
            if is_cloud_model_reference(model_ref):
                self.init_status_var.set(f"Cloud model loaded: {model_ref}")
            else:
                self.init_status_var.set(f"Model loaded: {Path(model_ref).name}")
        except Exception as exc:
            self.recognizer = None
            self.init_status_var.set(f"Model load failed: {exc}")
            self._set_status(f"Model load failed: {exc}")

    def _load_engine(self) -> None:
        if self.engine is not None:
            return
        engine_path = resolve_stockfish(self.app_config.stockfish_path)
        if not engine_path:
            self.engine_status_var.set("Engine not found")
            self.init_status_var.set("Stockfish not found. Engine reply disabled.")
            return
        try:
            self.engine = chess.engine.SimpleEngine.popen_uci(engine_path)
            self.engine_status_var.set(f"Engine loaded: {Path(engine_path).name}")
        except Exception as exc:
            self.engine = None
            self.engine_status_var.set(f"Engine failed: {exc}")
            self.init_status_var.set(f"Stockfish failed: {exc}")

    def _open_camera(self) -> None:
        if self.capture is not None:
            try:
                self.capture.release()
            except Exception:
                pass
            self.capture = None

        self.capture = open_camera(int(self.app_config.camera_index))
        if self.capture is None:
            self.init_status_var.set("Camera could not be opened. Check the camera index and permissions.")
            self._set_status("Camera could not be opened. Check the camera index and permissions.")
        else:
            self.init_status_var.set(f"Camera opened: index {self.app_config.camera_index}")

    def _start_workers(self) -> None:
        if self.capture is None:
            return
        self.stop_event.clear()
        if self.camera_thread is None or not self.camera_thread.is_alive():
            self.camera_thread = threading.Thread(target=self._camera_loop, daemon=True)
            self.camera_thread.start()
        if self.analysis_thread is None or not self.analysis_thread.is_alive():
            self.analysis_thread = threading.Thread(target=self._analysis_loop, daemon=True)
            self.analysis_thread.start()
        if self.hand_thread is None or not self.hand_thread.is_alive():
            self.hand_thread = threading.Thread(target=self._hand_loop, daemon=True)
            self.hand_thread.start()
        if self.tracking_thread is None or not self.tracking_thread.is_alive():
            self.tracking_thread = threading.Thread(target=self._tracking_loop, daemon=True)
            self.tracking_thread.start()

    # ------------------------------------------------------------------
    # Background loops
    # ------------------------------------------------------------------

    def _camera_loop(self) -> None:
        while not self.stop_event.is_set():
            if self.capture is None or self.is_paused:
                time.sleep(0.05)
                continue
            ok, frame = self.capture.read()
            if ok and frame is not None and frame.size > 0:
                with self.state_lock:
                    self.latest_frame = frame.copy()
            else:
                time.sleep(0.02)

    def _analysis_loop(self) -> None:
        while not self.stop_event.is_set():
            if self.is_paused:
                time.sleep(0.05)
                continue

            with self.state_lock:
                frame = None if self.latest_frame is None else self.latest_frame.copy()
                recognizer = self.recognizer
                calibration_points = list(self.calibration_points)
                last_board_view = None if self.last_detection_board_view is None else self.last_detection_board_view.copy()
                detection_count = int(self.latest_detection_count)

            if frame is None:
                time.sleep(0.03)
                continue

            if recognizer is None or not recognizer.is_ready:
                display = self._draw_guidance(frame, calibration_points, "Load the model to enable recognition.")
                with self.state_lock:
                    self.latest_display_frame = display
                time.sleep(0.03)
                continue

            if not recognizer.is_calibrated:
                display = self._draw_guidance(frame, calibration_points, self._calibration_message())
                with self.state_lock:
                    self.latest_display_frame = display
                    self.latest_vision_fen = None
                    self.latest_detection_count = 0
                time.sleep(0.03)
                continue

            if last_board_view is None:
                warped = recognizer.warp_frame(frame)
                last_board_view = recognizer.draw_board_grid(warped)

            display = self._compose_split_view(
                frame,
                last_board_view,
                detection_count,
                0,
                0,
            )

            with self.state_lock:
                self.latest_display_frame = display

            time.sleep(0.03)

    def _analyze_frame(self, frame: np.ndarray, recognizer: BoardRecognizer, stability_frames: int) -> tuple[np.ndarray, str, int, np.ndarray]:
        warped = recognizer.warp_frame(frame)
        detections = recognizer.detect(warped)
        filtered = [
            det
            for det in detections
            if float(det.get("confidence", 0.0)) >= DETECTION_CONFIDENCE_MIN
        ]
        board_state = recognizer.detections_to_board(filtered, warped.shape[1], warped.shape[0])
        curr_fen = board_state.board_fen()

        with self.state_lock:
            if curr_fen == self.candidate_fen:
                self.stable_count += 1
            else:
                self.candidate_fen = curr_fen
                self.stable_count = 1
                self.next_snapshot_at = 0.0

            stable = self.stable_count >= stability_frames
            expected_fen = self.prev_board_fen
            phase = self.phase
            human_color = self._human_color()

            if phase == "calibrating":
                self.status_message = self._calibration_message()
            elif phase == "waiting_human":
                if self.board.turn != human_color:
                    self.phase = "awaiting_engine"
                    self.status_message = "Engine to move. Click Engine reply."
                    self.step_status_var.set("Step 4/4: Engine reply")
                elif expected_fen is None:
                    self.prev_board_fen = curr_fen
                    self.candidate_move = None
                    self.candidate_move_streak = 0
                    self.candidate_miss_count = 0
                elif curr_fen == expected_fen:
                    self.candidate_move = None
                    self.candidate_move_streak = 0
                    self.candidate_miss_count = 0
                elif curr_fen != expected_fen:
                    delta_count = self._fen_delta_count(expected_fen, curr_fen)
                    if delta_count > 16:
                        # Heavy board jitter: keep current candidate for a short grace window.
                        if self.candidate_move is not None:
                            self.candidate_miss_count += 1
                            if self.candidate_miss_count > 3:
                                self.candidate_move = None
                                self.candidate_move_streak = 0
                                self.candidate_miss_count = 0
                        self.status_message = "Board noisy. Hold move for a moment so detection can stabilize."
                        move = None
                    else:
                        move = self._infer_human_move(expected_fen, curr_fen)
                    if move and move in self.board.legal_moves:
                        if self.candidate_move is not None and move.uci() == self.candidate_move.uci():
                            self.candidate_move_streak += 1
                        else:
                            self.candidate_move = move
                            self.candidate_move_streak = 1
                        self.candidate_miss_count = 0

                        # Confirm by either full-board stability or a repeated identical move candidate.
                        if stable or self.candidate_move_streak >= 2:
                            san = self.board.san(move)
                            side = "white" if self.board.turn == chess.WHITE else "black"
                            self.board.push(move)
                            self.move_history.append(
                                {
                                    "ply": len(self.board.move_stack),
                                    "source": "vision",
                                    "side": side,
                                    "san": san,
                                    "uci": move.uci(),
                                }
                            )
                            self._stamp_latest_human_move(time.strftime("%H:%M:%S"))
                            self.prev_board_fen = self.board.board_fen()
                            self.candidate_move = None
                            self.candidate_move_streak = 0
                            self.candidate_miss_count = 0
                            self.phase = "awaiting_engine"
                            self.status_message = f"Human move detected: {san}. Click Engine reply."
                            self.step_status_var.set("Step 4/4: Engine reply")
                            self.engine_status_var.set(f"Waiting to respond after {san}")
                            self.next_snapshot_at = 0.0
                        elif self.candidate_move is not None:
                            self.status_message = f"Candidate move: {self.board.san(self.candidate_move)} ({self.candidate_move_streak}/2)"
                    else:
                        if self.candidate_move is not None:
                            self.candidate_miss_count += 1
                            if self.candidate_miss_count > 2:
                                self.candidate_move = None
                                self.candidate_move_streak = 0
                                self.candidate_miss_count = 0
                        self.status_message = "Stable change detected, but no legal move matched yet."
            elif phase == "awaiting_engine":
                self.status_message = "Human move accepted. Click Engine reply to ask Stockfish for the next move."

        board_view = recognizer.draw_board_grid(warped.copy())
        board_view = recognizer.draw_detections(board_view, filtered)
        board_view = self._draw_overlay(board_view, stable, len(filtered), self.stable_count, stability_frames)

        # Light temporal blending reduces visual jitter in overlay boxes.
        if self.prev_board_overlay is not None and self.prev_board_overlay.shape == board_view.shape:
            board_view = cv2.addWeighted(self.prev_board_overlay, 0.35, board_view, 0.65, 0)
        self.prev_board_overlay = board_view.copy()

        display = self._compose_split_view(frame, board_view, len(filtered), self.stable_count, stability_frames)
        return display, curr_fen, len(filtered), board_view

    def _infer_human_move(self, expected_fen: str, curr_fen: str) -> Optional[chess.Move]:
        """Infer the human move with a tolerant fallback when board FEN is slightly noisy."""
        strict = BoardRecognizer.infer_move(expected_fen, curr_fen, self.board.turn)
        if strict is not None and strict in self.board.legal_moves:
            return strict

        turn_char = "w" if self.board.turn == chess.WHITE else "b"
        try:
            target_board = chess.Board(f"{curr_fen} {turn_char} KQkq - 0 1")
        except Exception:
            return None

        current_board = self.board.copy(stack=False)
        best_move: Optional[chess.Move] = None
        best_score = -10_000
        second_best = -10_000

        for move in current_board.legal_moves:
            test_board = current_board.copy(stack=False)
            test_board.push(move)

            total_match = 0
            occupancy_match = 0
            color_match = 0
            changed_squares = 0
            changed_match = 0
            for sq in chess.SQUARES:
                now_piece = current_board.piece_at(sq)
                after_piece = test_board.piece_at(sq)
                target_piece = target_board.piece_at(sq)

                if after_piece == target_piece:
                    total_match += 1
                if (after_piece is None) == (target_piece is None):
                    occupancy_match += 1
                if after_piece is not None and target_piece is not None and after_piece.color == target_piece.color:
                    color_match += 1
                if now_piece != after_piece:
                    changed_squares += 1
                    if after_piece == target_piece:
                        changed_match += 1

            score = (total_match * 2) + (occupancy_match * 2) + color_match + (changed_match * 10)
            if score > best_score:
                second_best = best_score
                best_score = score
                best_move = move
            elif score > second_best:
                second_best = score

        if best_move is None:
            return None

        test_board = current_board.copy(stack=False)
        test_board.push(best_move)
        total_match = sum(1 for sq in chess.SQUARES if test_board.piece_at(sq) == target_board.piece_at(sq))
        occupancy_match = sum(
            1 for sq in chess.SQUARES if (test_board.piece_at(sq) is None) == (target_board.piece_at(sq) is None)
        )
        changed_squares = sum(1 for sq in chess.SQUARES if current_board.piece_at(sq) != test_board.piece_at(sq))
        changed_match = sum(
            1
            for sq in chess.SQUARES
            if current_board.piece_at(sq) != test_board.piece_at(sq) and test_board.piece_at(sq) == target_board.piece_at(sq)
        )

        if total_match < 50:
            return None
        if occupancy_match < 58:
            return None
        if changed_squares > 0 and changed_match < max(1, changed_squares - 1):
            return None
        if best_score - second_best < 6:
            return None

        return best_move

    def _fen_delta_count(self, fen_a: str, fen_b: str) -> int:
        """Count piece-placement square differences between two board-only FENs."""
        try:
            board_a = chess.Board(f"{fen_a} w KQkq - 0 1")
            board_b = chess.Board(f"{fen_b} w KQkq - 0 1")
        except Exception:
            return 64
        return sum(1 for sq in chess.SQUARES if board_a.piece_at(sq) != board_b.piece_at(sq))

    def _compose_split_view(
        self,
        frame: np.ndarray,
        board_view: np.ndarray,
        detection_count: int,
        stable_count: int,
        stability_frames: int,
    ) -> np.ndarray:
        """Compose camera + board analysis without re-running inference."""
        # Clean split view: large camera on the left, board analysis panel on the right.
        preview_w = max(320, int(self.preview_width))
        preview_h = max(260, int(self.preview_height))
        display = np.zeros((preview_h, preview_w, 3), dtype=np.uint8)

        gap = 12
        margin = 10
        right_panel_w = int(preview_w * 0.30)
        left_panel_w = preview_w - right_panel_w - gap - (margin * 2)
        panel_h = preview_h - (margin * 2)

        cam_view, cam_rect = self._fit_with_letterbox(frame, left_panel_w, panel_h)
        board_size = min(right_panel_w, panel_h)
        board_fit = cv2.resize(board_view, (board_size, board_size), interpolation=cv2.INTER_AREA)

        left_x = margin
        left_y = margin
        right_x = left_x + left_panel_w + gap
        right_y = margin

        display[left_y:left_y + panel_h, left_x:left_x + left_panel_w] = cam_view
        self.last_camera_rect = (left_x + cam_rect[0], left_y + cam_rect[1], cam_rect[2], cam_rect[3])
        cv2.rectangle(display, (left_x - 1, left_y - 1), (left_x + left_panel_w + 1, left_y + panel_h + 1), (90, 100, 115), 1)
        cv2.putText(display, "Camera", (left_x + 6, left_y + 18), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (230, 230, 230), 1)

        panel_bg_h = max(panel_h, board_size + 84)
        if right_y + panel_bg_h > preview_h:
            panel_bg_h = preview_h - right_y
        cv2.rectangle(display, (right_x, right_y), (right_x + right_panel_w, right_y + panel_bg_h), (22, 27, 35), -1)
        cv2.rectangle(display, (right_x, right_y), (right_x + right_panel_w, right_y + panel_bg_h), (90, 100, 115), 1)
        display[right_y + 26:right_y + 26 + board_size, right_x:right_x + board_size] = board_fit
        cv2.putText(display, "Board Analysis", (right_x + 8, right_y + 18), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (235, 235, 235), 1)
        cv2.putText(
            display,
            f"Detections: {detection_count}",
            (right_x + 8, min(preview_h - 10, right_y + 26 + board_size + 24)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            (190, 200, 215),
            1,
        )
        return display

    def _draw_guidance(self, frame: np.ndarray, points: list[tuple[float, float]], message: str) -> np.ndarray:
        preview_w = max(320, int(self.preview_width))
        preview_h = max(260, int(self.preview_height))
        display, cam_rect = self._fit_with_letterbox(frame, preview_w, preview_h)
        self.last_camera_rect = cam_rect
        src_h, src_w = frame.shape[:2]
        sx = cam_rect[2] / max(1, src_w)
        sy = cam_rect[3] / max(1, src_h)
        for index, point in enumerate(points):
            px = int(cam_rect[0] + (point[0] * sx))
            py = int(cam_rect[1] + (point[1] * sy))
            cv2.circle(display, (px, py), 6, (0, 255, 255), -1)
            cv2.putText(display, str(index + 1), (px + 8, py - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
        cv2.putText(display, message, (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 200, 255), 2)
        return display

    def _on_canvas_resize(self, event: tk.Event) -> None:
        with self.state_lock:
            self.preview_width = max(320, int(event.width))
            self.preview_height = max(260, int(event.height))

    def _fit_with_letterbox(self, frame: np.ndarray, target_w: int, target_h: int) -> tuple[np.ndarray, tuple[int, int, int, int]]:
        """Resize while preserving aspect ratio; return image and inner camera rect (x, y, w, h)."""
        target_w = max(1, int(target_w))
        target_h = max(1, int(target_h))
        src_h, src_w = frame.shape[:2]
        if src_h <= 0 or src_w <= 0:
            blank = np.zeros((target_h, target_w, 3), dtype=np.uint8)
            return blank, (0, 0, target_w, target_h)

        scale = min(target_w / float(src_w), target_h / float(src_h))
        fit_w = max(1, int(round(src_w * scale)))
        fit_h = max(1, int(round(src_h * scale)))
        resized = cv2.resize(frame, (fit_w, fit_h), interpolation=cv2.INTER_AREA)

        canvas = np.zeros((target_h, target_w, 3), dtype=np.uint8)
        x = (target_w - fit_w) // 2
        y = (target_h - fit_h) // 2
        canvas[y:y + fit_h, x:x + fit_w] = resized
        return canvas, (x, y, fit_w, fit_h)

    def _draw_overlay(self, frame: np.ndarray, stable: bool, detection_count: int, stable_count: int, stability_frames: int) -> np.ndarray:
        overlay_color = (0, 220, 0) if stable else (0, 160, 255)
        turn_text = "WHITE" if self.board.turn == chess.WHITE else "BLACK"
        cv2.putText(frame, f"{('STABLE' if stable else 'SCANNING')} | DET {detection_count} | FR {stable_count}/{stability_frames}", (10, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, overlay_color, 2)
        cv2.putText(frame, f"TURN {turn_text} | MOVE {self.board.fullmove_number}", (10, 54), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
        human_text = "WHITE" if self._human_color() == chess.WHITE else "BLACK"
        cv2.putText(frame, f"YOU {human_text}", (10, 78), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
        if self.phase == "waiting_human":
            cv2.putText(frame, "YOUR MOVE", (10, BOARD_DISPLAY_SIZE - 16), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 200, 255), 2)
        elif self.phase == "awaiting_engine":
            cv2.putText(frame, "ENGINE READY", (10, BOARD_DISPLAY_SIZE - 16), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 220, 0), 2)
        elif self.phase == "calibrating":
            cv2.putText(frame, "CALIBRATION MODE", (10, BOARD_DISPLAY_SIZE - 16), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 220, 0), 2)
        return frame

    def _calibration_message(self) -> str:
        count = len(self.calibration_points)
        if count == 0:
            return "Calibration mode: click top-left, top-right, bottom-right, bottom-left."
        return f"Calibration mode: {count}/4 corners selected. Click the next corner."

    # ------------------------------------------------------------------
    # Actions
    # ------------------------------------------------------------------

    def trigger_manual_capture(self, event: Optional[tk.Event] = None) -> None:
        self._schedule_capture("manual", force_initial=False)

    def validate_starting_position(self) -> None:
        if ASSUME_STANDARD_START:
            with self.state_lock:
                self.board = chess.Board()
                self.prev_board_fen = self.board.board_fen()
                self.initial_board_validated = True
                self.phase = "waiting_human" if self.board.turn == self._human_color() else "awaiting_engine"
                self.status_message = "Standard start assumed. Waiting for the first move."
            self.step_status_var.set("Step 3/4: Human move")
            return
        self._schedule_capture("validate_start", force_initial=True)

    def _schedule_capture(self, reason: str, force_initial: bool) -> None:
        if self.capture_in_flight:
            self.status_message = "Capture already in progress."
            return
        self.capture_in_flight = True
        self.last_trigger_time = time.time()
        worker = threading.Thread(
            target=self._capture_and_process,
            args=(reason, force_initial),
            daemon=True,
        )
        worker.start()

    def _schedule_recapture(self, reason: str, force_initial: bool) -> None:
        if self.is_paused:
            return
        now = time.time()
        if (now - self.last_recapture_time) < RECAPTURE_DELAY_SEC:
            return
        self.last_recapture_time = now
        self.after(
            int(RECAPTURE_DELAY_SEC * 1000),
            lambda: self._schedule_capture(f"{reason}_retry", force_initial=force_initial),
        )

    def _capture_and_process(self, reason: str, force_initial: bool) -> None:
        try:
            time.sleep(CAPTURE_DELAY_SEC)

            with self.state_lock:
                recognizer = self.recognizer

            if recognizer is None or not recognizer.is_ready:
                self.status_message = "Load the model before capturing."
                return

            if not recognizer.is_calibrated:
                self.status_message = "Calibrate the board before capturing."
                return

            samples: list[dict[str, Optional[str]]] = []
            board_view = None
            detection_count = 0
            for idx in range(max(1, CAPTURE_SAMPLES)):
                with self.state_lock:
                    frame = None if self.latest_frame is None else self.latest_frame.copy()

                if frame is None:
                    time.sleep(CAPTURE_SAMPLE_DELAY)
                    continue

                warped = recognizer.warp_frame(frame)
                detections = recognizer.detect(warped)
                filtered = [
                    det
                    for det in detections
                    if float(det.get("confidence", 0.0)) >= DETECTION_CONFIDENCE_MIN
                ]
                state = recognizer.detections_to_state_dict(
                    filtered,
                    warped.shape[1],
                    warped.shape[0],
                    min_confidence=DETECTION_CONFIDENCE_MIN,
                )
                samples.append(state)
                detection_count = len(filtered)
                board_view = recognizer.draw_board_grid(warped.copy())
                board_view = recognizer.draw_detections(board_view, filtered)

                if idx < (CAPTURE_SAMPLES - 1) and CAPTURE_SAMPLE_DELAY > 0:
                    time.sleep(CAPTURE_SAMPLE_DELAY)

            if not samples:
                self.status_message = "No camera frame available."
                return

            all_squares = [chess.square_name(sq) for sq in chess.SQUARES]
            stable_state: dict[str, Optional[str]] = {sq: None for sq in all_squares}
            for sq in all_squares:
                label_counts: dict[str, int] = {}
                for sample_state in samples:
                    label = sample_state.get(sq)
                    if label:
                        label_counts[label] = label_counts.get(label, 0) + 1
                if label_counts:
                    best_label, best_count = max(label_counts.items(), key=lambda item: item[1])
                    if best_count >= STABLE_LABEL_MIN_COUNT:
                        stable_state[sq] = best_label

            curr_board = recognizer.state_dict_to_board(stable_state)
            curr_fen = curr_board.board_fen()

            if board_view is None:
                board_view = np.zeros((BOARD_DISPLAY_SIZE, BOARD_DISPLAY_SIZE, 3), dtype=np.uint8)

            if force_initial or not self.initial_board_validated:
                if ASSUME_STANDARD_START:
                    self.initial_board_validated = True
                    self.board = chess.Board()
                    self.prev_board_fen = self.board.board_fen()
                    self.phase = "waiting_human" if self.board.turn == self._human_color() else "awaiting_engine"
                    self.step_status_var.set(
                        "Step 3/4: Human move" if self.phase == "waiting_human" else "Step 4/4: Engine reply"
                    )
                    self.status_message = "Standard start assumed. Ready for moves."
                    self.last_invalid_squares = []
                    self.last_changed_squares = []
                    self._update_detection_snapshot(
                        stable_state,
                        curr_fen,
                        detection_count,
                        board_view,
                        reason,
                        [],
                        [],
                        0,
                        0,
                    )
                    return

                valid, mismatches = recognizer.validate_initial_state(
                    stable_state,
                    max_missing=START_MAX_MISSING,
                    max_extra=START_MAX_EXTRA,
                )
                if not valid:
                    board_view = self._highlight_squares(board_view, mismatches, (0, 0, 255))
                    self._update_detection_snapshot(
                        stable_state,
                        curr_fen,
                        detection_count,
                        board_view,
                        reason,
                        mismatches,
                        [],
                        0,
                        0,
                    )
                    self.status_message = "Board not in valid starting position. Reset pieces and retry."
                    self._schedule_recapture(reason, force_initial=True)
                    return

                self.initial_board_validated = True
                self.board = chess.Board()
                self.prev_board_fen = self.board.board_fen()
                self.phase = "waiting_human" if self.board.turn == self._human_color() else "awaiting_engine"
                self.step_status_var.set(
                    "Step 3/4: Human move" if self.phase == "waiting_human" else "Step 4/4: Engine reply"
                )
                self.status_message = "Initial board validated. Ready for moves."
                self.last_invalid_squares = []
                self.last_changed_squares = []
                self._update_detection_snapshot(
                    stable_state,
                    curr_fen,
                    detection_count,
                    board_view,
                    reason,
                    [],
                    [],
                    0,
                    0,
                )
                return

            if OCCUPANCY_ONLY:
                prev_state = recognizer.board_to_occupancy_state(self.board)
                curr_state = recognizer.to_occupancy_state(stable_state)
                changed_squares = self._diff_squares(prev_state, curr_state)
                move, best_score, second_best = recognizer.infer_move_from_occupancy(
                    self.board,
                    curr_state,
                    min_score=MOVE_MATCH_MIN_SCORE,
                    min_gap=MOVE_MATCH_MIN_GAP,
                )
            else:
                prev_state = recognizer.board_to_state_dict(self.board)
                changed_squares = self._diff_squares(prev_state, stable_state)
                move, best_score, second_best = recognizer.infer_move_from_state(
                    self.board,
                    stable_state,
                    min_score=MOVE_MATCH_MIN_SCORE,
                    min_gap=MOVE_MATCH_MIN_GAP,
                )
            board_view = self._highlight_squares(board_view, changed_squares, (0, 200, 255))

            if move is None:
                board_view = self._highlight_squares(board_view, changed_squares, (0, 0, 255))
                self._update_detection_snapshot(
                    stable_state,
                    curr_fen,
                    detection_count,
                    board_view,
                    reason,
                    changed_squares,
                    changed_squares,
                    best_score,
                    second_best,
                )
                squares_text = ", ".join(changed_squares[:6])
                if len(changed_squares) > 6:
                    squares_text += "..."
                self.status_message = (
                    f"No legal move matched. Changed: {squares_text or '-'} | "
                    f"Score {best_score}/{second_best}. Retry capture."
                )
                print(
                    f"[WARN] No legal move matched. Changed={changed_squares} "
                    f"Score={best_score} Second={second_best}"
                )
                self._schedule_recapture(reason, force_initial=False)
                return

            ok, engine_warning = self._validate_with_engine(move)
            if not ok:
                self._update_detection_snapshot(
                    stable_state,
                    curr_fen,
                    detection_count,
                    board_view,
                    reason,
                    [],
                    changed_squares,
                    best_score,
                    second_best,
                )
                self.status_message = f"Move rejected by engine: {move.uci()}. Retry capture."
                return

            san = self.board.san(move)
            side = "white" if self.board.turn == chess.WHITE else "black"
            self.board.push(move)
            self.move_history.append(
                {
                    "ply": len(self.board.move_stack),
                    "source": "vision",
                    "side": side,
                    "san": san,
                    "uci": move.uci(),
                }
            )
            self._stamp_latest_human_move(time.strftime("%H:%M:%S"))
            self.prev_board_fen = self.board.board_fen()
            self.phase = "awaiting_engine"
            self.step_status_var.set("Step 4/4: Engine reply")
            low_conf = best_score < (MOVE_MATCH_MIN_SCORE + 3)
            suffix = " (low confidence)" if low_conf else ""
            warning_text = " Stockfish disagrees." if engine_warning else ""
            self.status_message = f"Human move detected: {san}. Engine replying...{suffix}{warning_text}"
            print(f"[MOVE] {move.uci()} | FEN: {self.board.fen()}")
            if engine_warning:
                print(f"[WARN] Stockfish did not rank {move.uci()} in top PVs.")

            self._update_detection_snapshot(
                stable_state,
                curr_fen,
                detection_count,
                board_view,
                reason,
                [],
                changed_squares,
                best_score,
                second_best,
            )
            if AUTO_ENGINE_REPLY:
                self.after(int(ENGINE_AUTO_DELAY_SEC * 1000), self.apply_engine_move)
        except Exception as exc:
            message = str(exc)
            if "timed out" in message.lower() or "timeout" in message.lower():
                self.status_message = "Cloud timeout. Retry capture or use a local model."
            else:
                self.status_message = f"Capture failed: {exc}"
        finally:
            self.capture_in_flight = False

    def _update_detection_snapshot(
        self,
        state: dict[str, Optional[str]],
        curr_fen: str,
        detection_count: int,
        board_view: np.ndarray,
        reason: str,
        invalid_squares: list[str],
        changed_squares: list[str],
        best_score: int,
        second_best: int,
    ) -> None:
        with self.state_lock:
            self.last_detection_state = state
            self.last_detection_board_view = board_view
            self.latest_vision_fen = curr_fen
            self.latest_detection_count = int(detection_count)
            self.last_detection_reason = reason
            self.last_detection_score = best_score
            self.last_detection_second_score = second_best
            self.last_invalid_squares = list(invalid_squares)
            self.last_changed_squares = list(changed_squares)

    def _diff_squares(self, prev_state: dict[str, Optional[str]], curr_state: dict[str, Optional[str]]) -> list[str]:
        changed: list[str] = []
        for sq, prev_val in prev_state.items():
            if prev_val != curr_state.get(sq):
                changed.append(sq)
        return changed

    def _highlight_squares(self, board_view: np.ndarray, squares: list[str], color: tuple[int, int, int]) -> np.ndarray:
        if not squares:
            return board_view
        vis = board_view.copy()
        h, w = vis.shape[:2]
        sw = w / 8.0
        sh = h / 8.0
        for sq in squares:
            if not sq:
                continue
            file_char = sq[0].lower()
            rank_char = sq[1]
            if file_char < "a" or file_char > "h" or rank_char < "1" or rank_char > "8":
                continue
            file_idx = ord(file_char) - ord("a")
            rank_idx = 8 - int(rank_char)
            x1 = int(file_idx * sw)
            y1 = int(rank_idx * sh)
            x2 = int((file_idx + 1) * sw)
            y2 = int((rank_idx + 1) * sh)
            cv2.rectangle(vis, (x1, y1), (x2, y2), color, 2)
        return vis

    def _validate_with_engine(self, move: chess.Move) -> tuple[bool, bool]:
        if move not in self.board.legal_moves:
            return False, False
        if self.engine is None:
            return True, False
        try:
            engine_time = float(self.app_config.engine_time)
            info = self.engine.analyse(self.board, chess.engine.Limit(time=engine_time), multipv=5)
        except Exception:
            return True, False

        if isinstance(info, dict):
            info = [info]
        top_moves = []
        for entry in info:
            pv = entry.get("pv") if isinstance(entry, dict) else None
            if pv:
                top_moves.append(pv[0])
        if not top_moves:
            return True, False
        in_top = any(move.uci() == top.uci() for top in top_moves)
        return True, (not in_top)

    def _hand_loop(self) -> None:
        prev_gray = None
        while not self.stop_event.is_set():
            if self.is_paused:
                time.sleep(0.1)
                continue

            with self.state_lock:
                frame = None if self.latest_frame is None else self.latest_frame.copy()
                calibrated = self.recognizer is not None and self.recognizer.is_calibrated
                corners = list(self.calibration_points)

            if frame is None:
                time.sleep(0.1)
                continue

            roi = frame
            if calibrated and len(corners) == 4:
                xs = [int(p[0]) for p in corners]
                ys = [int(p[1]) for p in corners]
                x1 = max(0, min(xs))
                x2 = min(frame.shape[1], max(xs))
                y1 = max(0, min(ys))
                y2 = min(frame.shape[0], max(ys))
                if x2 - x1 > 10 and y2 - y1 > 10:
                    roi = frame[y1:y2, x1:x2]

            gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            if MOTION_BLUR > 0:
                gray = cv2.GaussianBlur(gray, (MOTION_BLUR, MOTION_BLUR), 0)

            if prev_gray is None or prev_gray.shape != gray.shape:
                prev_gray = gray
                time.sleep(0.1)
                continue

            diff = cv2.absdiff(prev_gray, gray)
            _, thresh = cv2.threshold(diff, MOTION_DIFF_THRESHOLD, 255, cv2.THRESH_BINARY)
            motion_ratio = float(np.count_nonzero(thresh)) / float(thresh.size)
            prev_gray = gray
            now = time.time()

            if motion_ratio >= MOTION_RATIO_TRIGGER:
                self.hand_present = True
                self.hand_last_seen = now
            else:
                if self.hand_present and (now - self.hand_last_seen) >= HAND_ABSENCE_SECONDS:
                    if (now - self.last_trigger_time) >= HAND_TRIGGER_COOLDOWN:
                        self._schedule_capture("hand_left", force_initial=False)
                    self.hand_present = False

            time.sleep(0.1)

    def _tracking_loop(self) -> None:
        """Background loop reserved for future tracking enhancements."""
        while not self.stop_event.is_set():
            if self.is_paused:
                time.sleep(0.1)
                continue
            with self.state_lock:
                frame = None if self.latest_frame is None else self.latest_frame.copy()
            if frame is None:
                time.sleep(0.1)
                continue
            self.tracking_prev_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            time.sleep(0.2)

    def begin_calibration(self) -> None:
        with self.state_lock:
            if self.recognizer is None:
                self.status_message = "Load the model before calibration."
                return
            self.calibration_mode = True
            self.initial_board_validated = False
            self.last_detection_state = None
            self.last_detection_board_view = None
            self.last_invalid_squares = []
            self.last_changed_squares = []
            self.phase = "calibrating"
            self.calibration_points.clear()
            self.candidate_fen = None
            self.candidate_move = None
            self.candidate_move_streak = 0
            self.candidate_miss_count = 0
            self.next_snapshot_at = 0.0
            self.stable_count = 0
            if self.recognizer is not None:
                self.recognizer.warp_matrix = None
            self.status_message = "Click the 4 board corners on the live view: top-left, top-right, bottom-right, bottom-left."
            self.canvas_click_hint.set("Calibration mode: click the 4 corners in order on the live board")
            self.calibration_status_var.set("Calibration pending")
            self.step_status_var.set("Step 2/4: Calibrate")
        self._refresh_connection_text()

    def on_canvas_click(self, event: tk.Event) -> None:
        with self.state_lock:
            if not self.calibration_mode or self.recognizer is None:
                return
            if len(self.calibration_points) >= 4:
                return

            src_w = PREVIEW_WIDTH
            src_h = PREVIEW_HEIGHT
            if self.latest_frame is not None and self.latest_frame.size > 0:
                src_h, src_w = self.latest_frame.shape[:2]

            cam_x, cam_y, cam_w, cam_h = self.last_camera_rect
            if cam_w <= 0 or cam_h <= 0:
                cam_x, cam_y, cam_w, cam_h = 0, 0, self.preview_width, self.preview_height

            if event.x < cam_x or event.x >= cam_x + cam_w or event.y < cam_y or event.y >= cam_y + cam_h:
                self.status_message = "Click inside the camera image area for calibration."
                return

            clamped_x = min(max(event.x, cam_x), cam_x + cam_w - 1)
            clamped_y = min(max(event.y, cam_y), cam_y + cam_h - 1)
            rel_x = clamped_x - cam_x
            rel_y = clamped_y - cam_y

            mapped_x = float(rel_x) * (float(src_w) / float(cam_w))
            mapped_y = float(rel_y) * (float(src_h) / float(cam_h))
            self.calibration_points.append((mapped_x, mapped_y))
            self.app_config.calibration_points = [[x, y] for x, y in self.calibration_points]
            if len(self.calibration_points) == 4:
                try:
                    self.recognizer.calibrate(self.calibration_points)
                    self.recognizer.BOARD_SIZE = BOARD_DISPLAY_SIZE
                    self.calibration_mode = False
                    self.phase = "idle"
                    self.prev_board_fen = None
                    self.initial_board_validated = False
                    self.candidate_fen = None
                    self.stable_count = 0
                    if ASSUME_STANDARD_START:
                        self.board = chess.Board()
                        self.prev_board_fen = self.board.board_fen()
                        self.initial_board_validated = True
                        self.phase = "waiting_human" if self.board.turn == self._human_color() else "awaiting_engine"
                        self.status_message = "Calibration complete. Waiting for the first move."
                        self.canvas_click_hint.set("Calibration complete. Make a move on the board.")
                        self.calibration_status_var.set("Calibration ready")
                        self.step_status_var.set("Step 3/4: Human move")
                    else:
                        self.status_message = "Calibration complete. Validate the starting position before play."
                        self.canvas_click_hint.set("Calibration complete. Click Validate start to confirm the board.")
                        self.calibration_status_var.set("Calibration ready")
                        self.step_status_var.set("Step 2/4: Validate start")
                    self.save_settings()
                except Exception as exc:
                    self.calibration_points.pop()
                    self.status_message = f"Calibration failed: {exc}"
            else:
                self.status_message = f"Calibration point {len(self.calibration_points)}/4 set."

    def clear_calibration(self) -> None:
        with self.state_lock:
            self.calibration_mode = False
            self.calibration_points.clear()
            self.app_config.calibration_points = []
            self.initial_board_validated = False
            self.last_detection_state = None
            self.last_detection_board_view = None
            self.last_invalid_squares = []
            self.last_changed_squares = []
            if self.recognizer is not None:
                self.recognizer.warp_matrix = None
            self.phase = "idle"
            self.prev_board_fen = None
            self.candidate_fen = None
            self.candidate_move = None
            self.candidate_move_streak = 0
            self.candidate_miss_count = 0
            self.next_snapshot_at = 0.0
            self.stable_count = 0
            self.status_message = "Calibration cleared. Click Calibrate to start again."
            self.canvas_click_hint.set("Click Calibrate, then mark TL, TR, BR, BL on the board.")
            self.calibration_status_var.set("Calibration pending")
            self.step_status_var.set("Step 2/4: Calibrate")
        self.save_settings()
        self._refresh_connection_text()

    def new_game(self) -> None:
        if not messagebox.askyesno("New game", "Reset the virtual board and clear move history?"):
            return
        with self.state_lock:
            self.board = chess.Board()
            self.move_history.clear()
            self.initial_board_validated = bool(ASSUME_STANDARD_START)
            self.last_detection_state = None
            self.last_detection_board_view = None
            self.last_invalid_squares = []
            self.last_changed_squares = []
            if not (self.recognizer and self.recognizer.is_calibrated):
                self.phase = "idle"
                self.prev_board_fen = None
            else:
                self.phase = "waiting_human" if self.board.turn == self._human_color() else "awaiting_engine"
                self.prev_board_fen = self.board.board_fen()
            self.candidate_fen = None
            self.candidate_move = None
            self.candidate_move_streak = 0
            self.candidate_miss_count = 0
            self.next_snapshot_at = 0.0
            self.stable_count = 0
            self.move_time_var.set("Last human move time: -")
            human_side = str(self.app_config.human_side).strip().capitalize()
            engine_side = "Black" if human_side == "White" else "White"
            if ASSUME_STANDARD_START and self.phase in {"waiting_human", "awaiting_engine"}:
                self.status_message = f"New game started. You are {human_side}, engine is {engine_side}. Waiting for moves."
                self.step_status_var.set("Step 3/4: Human move" if self.phase == "waiting_human" else "Step 4/4: Engine reply")
            else:
                self.status_message = f"New game started. You are {human_side}, engine is {engine_side}. Sync the real board."
                self.step_status_var.set("Step 3/4: Human move" if self.phase == "waiting_human" else "Step 1/4: Setup")
        self._refresh_connection_text()

    def apply_engine_move(self) -> None:
        with self.state_lock:
            if self.engine is None:
                self.status_message = "Stockfish is not loaded. Check the engine path."
                return
            if self.board.is_game_over():
                self.status_message = "The game is already over. Start a new game."
                return

            if self.board.turn != self._engine_color():
                self.status_message = "Your move is not confirmed yet. Wait 1-2 snapshots or enter Manual UCI move."
                return
            if self.phase != "awaiting_engine":
                self.phase = "awaiting_engine"
            engine_time = float(self.app_config.engine_time)

        try:
            result = self.engine.play(self.board, chess.engine.Limit(time=engine_time))
        except Exception as exc:
            self._set_status(f"Engine failed: {exc}")
            self.engine_status_var.set(f"Engine failed: {exc}")
            return

        move = result.move
        if move is None or move not in self.board.legal_moves:
            self._set_status("Engine returned no legal move.")
            return

        with self.state_lock:
            san = self.board.san(move)
            side = "white" if self.board.turn == chess.WHITE else "black"
            self.board.push(move)
            self.move_history.append(
                {
                    "ply": len(self.board.move_stack),
                    "source": "engine",
                    "side": side,
                    "san": san,
                    "uci": move.uci(),
                }
            )
            self.prev_board_fen = self.board.board_fen()
            self.phase = "sync_board"
            self.candidate_fen = None
            self.candidate_move = None
            self.candidate_move_streak = 0
            self.next_snapshot_at = 0.0
            self.stable_count = 0
            self.status_message = f"Engine move: {san}. Place the piece on the board, then wait for sync."
            self.engine_status_var.set(f"Last engine move: {san}")
            self.step_status_var.set("Step 3/4: Human move")

    def play_manual_move(self) -> None:
        move_text = self.manual_move_var.get().strip()
        if not move_text:
            self._set_status("Enter a UCI move first.")
            return

        with self.state_lock:
            move, error = self._parse_manual_move(move_text, self.board)
            if move is None:
                self.status_message = error
                return
            if move not in self.board.legal_moves:
                self.status_message = f"Illegal move: {move_text}"
                return
            san = self.board.san(move)
            side = "white" if self.board.turn == chess.WHITE else "black"
            self.board.push(move)
            self.move_history.append(
                {
                    "ply": len(self.board.move_stack),
                    "source": "manual",
                    "side": side,
                    "san": san,
                    "uci": move.uci(),
                }
            )
            self._stamp_latest_human_move(time.strftime("%H:%M:%S"))
            self.prev_board_fen = self.board.board_fen()
            self.phase = "sync_board"
            self.candidate_fen = None
            self.candidate_move = None
            self.candidate_move_streak = 0
            self.candidate_miss_count = 0
            self.stable_count = 0
            self.status_message = f"Manual move applied: {san}."
            self.step_status_var.set("Step 3/4: Human move")

    def _stamp_latest_human_move(self, stamp: str) -> bool:
        human_side = "black" if self._human_color() == chess.BLACK else "white"
        for entry in reversed(self.move_history):
            if str(entry.get("side", "")).lower() == human_side:
                entry["time"] = stamp
                self.move_time_var.set(f"Last human move time: {stamp}")
                return True
        return False

    def mark_move_time(self) -> None:
        stamp = time.strftime("%H:%M:%S")
        with self.state_lock:
            if self._stamp_latest_human_move(stamp):
                self.status_message = f"Move time marked: {stamp}."
            else:
                self.status_message = "No human move in history to mark yet."

    def _parse_manual_move(self, text: str, board: chess.Board) -> tuple[Optional[chess.Move], str]:
        """Parse manual input in UCI, SAN, or shorthand destination form."""
        raw = text.strip()
        cleaned = raw.lower().replace(" ", "")

        # 1) UCI format, e.g. e2e4, e7e8q
        try:
            move = chess.Move.from_uci(cleaned)
            if move in board.legal_moves:
                return move, ""
        except ValueError:
            pass

        # 2) SAN format, e.g. e4, Nf3, exd5, O-O
        try:
            move = board.parse_san(raw)
            if move in board.legal_moves:
                return move, ""
        except ValueError:
            pass

        # 3) Shorthand destination format: e4 or pe4 or ne5
        match = re.fullmatch(r"([kqrbnp]?)([a-h][1-8])", cleaned)
        if match:
            piece_code, destination = match.groups()
            to_square = chess.parse_square(destination)
            candidates = [mv for mv in board.legal_moves if mv.to_square == to_square]

            if piece_code:
                piece_map = {
                    "k": chess.KING,
                    "q": chess.QUEEN,
                    "r": chess.ROOK,
                    "b": chess.BISHOP,
                    "n": chess.KNIGHT,
                    "p": chess.PAWN,
                }
                target_piece = piece_map[piece_code]
                filtered: list[chess.Move] = []
                for mv in candidates:
                    piece = board.piece_at(mv.from_square)
                    if piece and piece.piece_type == target_piece:
                        filtered.append(mv)
                candidates = filtered

            if len(candidates) == 1:
                return candidates[0], ""
            if len(candidates) == 0:
                return None, f"No legal move matches '{raw}'."
            return None, f"Ambiguous move '{raw}'. Use UCI like e2e4."

        return None, f"Invalid move: {raw}. Use SAN (e4) or UCI (e2e4)."

    def toggle_pause(self) -> None:
        self.is_paused = not self.is_paused
        self.status_message = "Capture paused." if self.is_paused else "Capture resumed."
        self.status_var.set(self.status_message)

    def _set_status(self, message: str) -> None:
        with self.state_lock:
            self.status_message = message

    def show_help(self) -> None:
        messagebox.showinfo(
            "How to use RoboChess",
            "1. Load the model, Stockfish, and camera settings.\n"
            "2. Click Init.\n"
            "3. Click Calibrate and then click TL, TR, BR, BL on the live board.\n"
            "4. Click Validate start to confirm the initial position.\n"
            "5. Make a move on the real board, then press Space or Capture.\n"
            "6. Click Engine reply to ask Stockfish to move.\n"
            "7. Use New game to reset the virtual board.",
        )

    def show_about(self) -> None:
        messagebox.showinfo(
            "About RoboChess",
            "RoboChess Control Center\nA desktop interface for chessboard recognition and Stockfish play.",
        )

    # ------------------------------------------------------------------
    # Rendering and lifecycle
    # ------------------------------------------------------------------

    def _refresh_ui_state(self) -> None:
        self.board_fen_var.set(f"FEN: {self.board.board_fen()}")
        human_side = str(self.app_config.human_side).strip().capitalize()
        engine_side = "Black" if human_side == "White" else "White"
        self.turn_var.set(
            f"Turn: {'White' if self.board.turn == chess.WHITE else 'Black'} | Move: {self.board.fullmove_number} | You: {human_side} | Engine: {engine_side}"
        )
        self.phase_var.set(f"Phase: {self.phase}")
        init_state = "ready" if self.initial_board_validated else "pending"
        self.calibration_status_var.set(
            f"Calibration: {'ready' if self.recognizer and self.recognizer.is_calibrated else 'pending'} | Start: {init_state}"
        )
        self._refresh_connection_text()

    def _refresh_ui(self) -> None:
        with self.state_lock:
            display_frame = None if self.latest_display_frame is None else self.latest_display_frame.copy()
            board = self.board.copy()
            history = list(self.move_history)
            current_status = self.status_message
            current_phase = self.phase
            vision_fen = self.latest_vision_fen
            detection_count = self.latest_detection_count
            match_score = int(self.last_detection_score)
            match_second = int(self.last_detection_second_score)
            reason = str(self.last_detection_reason)
            preview_w = max(320, int(self.preview_width))
            preview_h = max(260, int(self.preview_height))

        if display_frame is not None:
            rgb = cv2.cvtColor(display_frame, cv2.COLOR_BGR2RGB)
            image = Image.fromarray(rgb)
            image = image.resize((preview_w, preview_h), Image.Resampling.LANCZOS)
            photo = ImageTk.PhotoImage(image=image)
            self.display_image = photo
            self.canvas.delete("all")
            self.canvas.create_image(0, 0, anchor="nw", image=photo)

        self.status_var.set(current_status)
        self._refresh_connection_text()
        self.board_fen_var.set(f"FEN: {board.board_fen()}")
        self.fen_var.set(f"FEN: {board.board_fen()}")
        reason_text = f" | Trigger: {reason}" if reason else ""
        score_text = f" | Match: {match_score}/{match_second}" if match_score or match_second else ""
        self.vision_var.set(
            f"Vision: {vision_fen if vision_fen else '-'} | Detections: {detection_count}{score_text}{reason_text}"
        )
        human_side = str(self.app_config.human_side).strip().capitalize()
        engine_side = "Black" if human_side == "White" else "White"
        self.turn_var.set(
            f"Turn: {'White' if board.turn == chess.WHITE else 'Black'} | Move: {board.fullmove_number} | You: {human_side} | Engine: {engine_side} | Legal: {sum(1 for _ in board.legal_moves)}"
        )
        self.phase_var.set(f"Phase: {current_phase}")
        init_state = "ready" if self.initial_board_validated else "pending"
        self.calibration_status_var.set(
            f"Calibration: {'ready' if self.recognizer and self.recognizer.is_calibrated else 'pending'} | Start: {init_state}"
        )
        self._update_board_text(board)
        self._update_history(history)

        self.after(40, self._refresh_ui)

    def _update_board_text(self, board: chess.Board) -> None:
        # Display the current board as a clean monospace diagram.
        # This keeps the game state readable even without looking at the live video.
        if not hasattr(self, "board_text"):
            return
        self.board_text.delete("1.0", tk.END)
        self.board_text.insert(tk.END, str(board))

    def _update_history(self, history: list[dict]) -> None:
        if not hasattr(self, "history_listbox"):
            return
        self.history_listbox.delete(0, tk.END)
        for move in history[-50:]:
            move_time = str(move.get("time", "-")).strip() or "-"
            self.history_listbox.insert(
                tk.END,
                f"{move['ply']:>2} | {move['source']:<7} | {move['side']:<5} | {move['san']:<8} | {move['uci']} | {move_time}",
            )

    def on_close(self) -> None:
        self.stop_event.set()
        self.save_settings()
        if self.capture is not None:
            try:
                self.capture.release()
            except Exception:
                pass
        if self.engine is not None:
            try:
                self.engine.quit()
            except Exception:
                pass
        self.destroy()


def main() -> None:
    app = RoboChessControlCenter()
    app.mainloop()


if __name__ == "__main__":
    main()
