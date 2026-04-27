# Pi Agent

Edge client that runs on each Raspberry Pi. It connects the board detection pipeline to the backend API.

## Setup

1. Create a `.env` with:

```
ROBOCHESS_API_BASE=http://<backend-ip>:8000
ROBOCHESS_WS_BASE=ws://<backend-ip>:8000/ws
ROBOCHESS_DEVICE_ID=<device_id>
ROBOCHESS_DEVICE_SECRET=<device_secret>
ROBOCHESS_HEARTBEAT_SECONDS=10
ROBOCHESS_BLE_ENABLED=0
ROBOCHESS_BLE_ADVERTISE_MODE=bluez
ROBOCHESS_BLE_SERVICE_UUID=0000f00d-0000-1000-8000-00805f9b34fb
ROBOCHESS_BLE_TOKEN_REFRESH_SECONDS=120
```

2. Run the agent:

```
python -m pi_agent.main
```

## Integrate detection

Edit `vision_adapter.py` to call your existing detection code and return `(uci_move, expected_version)`.

## BLE Notes

- Set `ROBOCHESS_BLE_ENABLED=1` on Raspberry Pi to advertise a BLE token for pairing.
- The agent requests a short-lived token from `/device/ble/token` and advertises it.
- `ROBOCHESS_BLE_ADVERTISE_MODE=bluez` uses `bluetoothctl` for advertising.
- For PC/dev mode, keep using pairing codes instead of BLE.
