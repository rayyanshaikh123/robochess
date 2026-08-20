from fastapi import APIRouter, Depends

from backend.api.schemas import (
    ApiResponse,
    DeviceBleLinkRequest,
    DeviceClaimRequest,
    DeviceConnectRequest,
    DeviceLinkRequest,
    DeviceOnboardingRequest,
    DeviceRegisterRequest,
    DeviceStatusUpdateRequest,
)
from backend.core.dependencies import get_current_device_id, get_current_user_id, rate_limit
from backend.db.client import get_db
from backend.services.device_service import (
    connect_device,
    create_ble_pair_token,
    create_onboarding_token,
    claim_device,
    disconnect_device,
    get_device_status,
    heartbeat_device,
    link_device,
    link_device_ble,
    list_devices,
    register_device,
    unlink_device,
    update_device_status,
)
from backend.utils.helpers import error, ok

router = APIRouter()


@router.post("/register", response_model=ApiResponse)
async def register(
    payload: DeviceRegisterRequest,
    db=Depends(get_db),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await register_device(db, payload.hardware_id)
    if err:
        return error(err)
    return ok("Device registered", data)


@router.post("/link", response_model=ApiResponse)
async def link(
    payload: DeviceLinkRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await link_device(db, user_id, payload.pairing_code)
    if err:
        return error(err)
    return ok("Device linked", data)


@router.post("/ble/token", response_model=ApiResponse)
async def ble_token(
    db=Depends(get_db),
    device_id: str = Depends(get_current_device_id),
) -> ApiResponse:
    data, err = await create_ble_pair_token(db, device_id)
    if err:
        return error(err)
    return ok("BLE token issued", data)


@router.post("/onboarding-token", response_model=ApiResponse)
async def onboarding_token(
    payload: DeviceOnboardingRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await create_onboarding_token(db, user_id, payload.device_id)
    if err:
        return error(err)
    return ok("Onboarding token issued", data)


@router.post("/claim", response_model=ApiResponse)
async def claim(
    payload: DeviceClaimRequest,
    db=Depends(get_db),
    device_id: str = Depends(get_current_device_id),
) -> ApiResponse:
    data, err = await claim_device(db, device_id, payload.onboarding_token)
    if err:
        return error(err)
    return ok("Device claimed", data)


@router.post("/status", response_model=ApiResponse)
async def update_status(
    payload: DeviceStatusUpdateRequest,
    db=Depends(get_db),
    device_id: str = Depends(get_current_device_id),
) -> ApiResponse:
    data, err = await update_device_status(db, device_id, payload.model_dump())
    if err:
        return error(err)
    return ok("Device status updated", data)


@router.post("/ble/link", response_model=ApiResponse)
async def ble_link(
    payload: DeviceBleLinkRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await link_device_ble(db, user_id, payload.token)
    if err:
        return error(err)
    return ok("Device linked", data)


@router.post("/connect", response_model=ApiResponse)
async def connect(
    payload: DeviceConnectRequest,
    db=Depends(get_db),
    _=Depends(rate_limit),
) -> ApiResponse:
    data, err = await connect_device(db, payload.device_id, payload.device_secret)
    if err:
        return error(err)
    return ok("Device connected", data)


@router.post("/disconnect", response_model=ApiResponse)
async def disconnect(
    db=Depends(get_db),
    device_id: str = Depends(get_current_device_id),
) -> ApiResponse:
    await disconnect_device(db, device_id)
    return ok("Device disconnected", {"device_id": device_id})


@router.post("/heartbeat", response_model=ApiResponse)
async def heartbeat(
    db=Depends(get_db),
    device_id: str = Depends(get_current_device_id),
) -> ApiResponse:
    await heartbeat_device(db, device_id)
    return ok("ok", {"device_id": device_id})


@router.get("/status/{device_id}", response_model=ApiResponse)
async def status(
    device_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await get_device_status(db, device_id, user_id)
    if err:
        return error(err)
    return ok("ok", data)


@router.get("/list", response_model=ApiResponse)
async def list_user_devices(
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    devices = await list_devices(db, user_id)
    return ok("ok", {"items": devices})


@router.post("/unlink/{device_id}", response_model=ApiResponse)
async def unlink(
    device_id: str,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    success, err = await unlink_device(db, user_id, device_id)
    if err:
        return error(err)
    return ok("Device unlinked", {"device_id": device_id, "unlinked": success})
