import threading
import time

from pi_agent.api_client import DeviceApiClient


class HeartbeatWorker:
    def __init__(self, api: DeviceApiClient, device_id: str, interval: int) -> None:
        self.api = api
        self.device_id = device_id
        self.interval = max(5, int(interval))
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
                self.api.heartbeat(self.device_id)
            except Exception:
                pass
            time.sleep(self.interval)
