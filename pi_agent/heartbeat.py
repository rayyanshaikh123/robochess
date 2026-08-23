import threading
import time
from collections.abc import Callable

from pi_agent.api_client import DeviceApiClient


class HeartbeatWorker:
    def __init__(
        self, api: DeviceApiClient, device_id: str, interval: int,
        device_secret: str | None = None,
        session_snapshot: Callable[[], dict | None] | None = None,
        device_secret_provider: Callable[[], str | None] | None = None,
    ) -> None:
        self.api = api
        self.device_id = device_id
        self.interval = max(5, int(interval))
        self.device_secret = device_secret
        self.device_secret_provider = device_secret_provider
        self.session_snapshot = session_snapshot
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                if not self.api.device_token:
                    secret = (
                        self.device_secret_provider()
                        if self.device_secret_provider
                        else self.device_secret
                    )
                    if not secret:
                        raise RuntimeError("No device secret configured")
                    self.api.connect(self.device_id, secret)
                snapshot = self.session_snapshot() if self.session_snapshot else None
                if snapshot:
                    self.api.sync_session(snapshot)
                self.api.heartbeat(self.device_id)
            except Exception:
                # Token is refreshed on the next interval after a network loss.
                self.api.device_token = None
            time.sleep(self.interval)
