from fastapi import APIRouter

from backend.api.auth import router as auth_router
from backend.api.devices import router as device_router
from backend.api.puzzles import router as puzzles_router
from backend.api.routes import router as core_router

api_router = APIRouter()
api_router.include_router(core_router)
api_router.include_router(auth_router, prefix="/auth", tags=["auth"])
api_router.include_router(device_router, prefix="/device", tags=["device"])
api_router.include_router(puzzles_router, prefix="/puzzles", tags=["puzzles"])
