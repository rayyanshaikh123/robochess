"""Pi-local setup readiness evaluation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class SetupStage:
    key: str
    ok: bool
    required: bool
    message: str
    details: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "ok": self.ok,
            "required": self.required,
            "message": self.message,
            "details": self.details,
        }


class SetupReadiness:
    def __init__(self, vision_mode: str = "cloud", vision_require_internet: bool = True) -> None:
        self.vision_mode = vision_mode
        self.vision_require_internet = vision_require_internet
        self._starting_position_valid = False

    def mark_starting_position(self, valid: bool) -> None:
        self._starting_position_valid = bool(valid)

    @property
    def starting_position_valid(self) -> bool:
        return self._starting_position_valid

    def evaluate(
        self,
        network: dict[str, Any],
        detector: dict[str, Any],
        calibrated: bool,
        gantry: dict[str, Any] | None,
    ) -> dict[str, Any]:
        internet_required = self.vision_mode == "cloud" and self.vision_require_internet
        network_ok = bool(network.get("internet_available")) if internet_required else bool(network.get("wifi_connected"))
        stages = [
            SetupStage(
                "wifi_ready",
                network_ok,
                internet_required,
                "Internet is available" if network_ok else ("Pi internet is required for Roboflow" if internet_required else "Pi Wi-Fi is connected"),
                network,
            ),
            SetupStage(
                "camera_ready",
                bool(detector.get("camera", {}).get("opened")) or bool(detector.get("camera", {}).get("capture_devices")),
                True,
                "Camera is available" if (bool(detector.get("camera", {}).get("opened")) or bool(detector.get("camera", {}).get("capture_devices"))) else "Connect a camera to the Pi",
                detector.get("camera", {}),
            ),
            SetupStage(
                "roboflow_ready",
                bool(detector.get("model_available")) and (not internet_required or bool(network.get("internet_available"))),
                self.vision_mode == "cloud",
                "Roboflow detector is ready" if detector.get("model_available") else detector.get("last_error", "Roboflow detector is not configured"),
                {"vision": detector, "internet_required": internet_required},
            ),
            SetupStage(
                "calibrated",
                calibrated,
                True,
                "Board calibration is saved" if calibrated else "Calibrate the board camera",
                {},
            ),
            SetupStage(
                "starting_position_valid",
                self._starting_position_valid,
                False,
                "Starting position is valid" if self._starting_position_valid else "Validate the pieces in the starting position",
                {},
            ),
            SetupStage(
                "gantry_homed",
                bool(gantry and gantry.get("homed") is True),
                True,
                "Gantry is homed" if gantry and gantry.get("homed") is True else "Home the gantry",
                gantry or {},
            ),
        ]
        ready = all(not stage.required or stage.ok for stage in stages)
        return {
            "ready": ready,
            "vision_mode": self.vision_mode,
            "backend_required": False,
            "stages": [stage.to_dict() for stage in stages],
            "missing": [stage.key for stage in stages if stage.required and not stage.ok],
        }
