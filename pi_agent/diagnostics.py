"""Read-only local diagnostics: python -m pi_agent.diagnostics."""

from __future__ import annotations

import shutil

from pi_agent.config import BLE_ADAPTER, BLE_ENABLED, DEVICE_ID, STOCKFISH_PATH, UNO_PORT, UNO_SIMULATOR
from pi_agent.session_store import SessionStore


def main() -> None:
    session = SessionStore().load()
    print(f"device_id: {DEVICE_ID or '<missing>'}")
    print(f"stockfish: {shutil.which(STOCKFISH_PATH) or STOCKFISH_PATH} ({'found' if shutil.which(STOCKFISH_PATH) else 'not found'})")
    print(f"ble: {'enabled' if BLE_ENABLED else 'disabled'}; adapter: {BLE_ADAPTER or 'auto'}")
    print(f"uno: {'simulator' if UNO_SIMULATOR else UNO_PORT or '<missing serial port>'}")
    if session:
        print(f"session: {session.session_id}; version={session.version}; phase={session.phase.value}")
    else:
        print("session: none")


if __name__ == "__main__":
    main()
