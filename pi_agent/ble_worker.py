import threading
import time

from pi_agent.api_client import DeviceApiClient
from pi_agent.ble_advertiser import BleAdvertiser


class BleTokenWorker:
    def __init__(
        self,
        api: DeviceApiClient,
        advertiser: BleAdvertiser,
        interval: int,
    ) -> None:
        self.api = api
        self.advertiser = advertiser
        self.interval = max(10, int(interval))
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
        self.advertiser.stop()

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                data = self.api.request_ble_token()
                token = data.get("ble_pair_token")
                if token:
                    self.advertiser.start(token)
            except Exception:
                pass
            time.sleep(self.interval)
