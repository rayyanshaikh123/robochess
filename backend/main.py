from contextlib import asynccontextmanager
from fastapi import FastAPI
from pathlib import Path
import sys

if __package__ is None:
    sys.path.append(str(Path(__file__).resolve().parents[1]))

from backend.api.router import api_router
from backend.core.game_manager import GameManager
from backend.core.logging import configure_logging, request_logging_middleware
from backend.core.config import load_settings
from backend.db.client import close_db, init_db
from backend.realtime.manager import manager as ws_manager
from backend.realtime.redis_pubsub import RedisPubSub

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db(app)
    settings = load_settings()
    if settings.redis_url:
        pubsub = RedisPubSub(settings.redis_url, settings.redis_channel, ws_manager)
        await pubsub.start()
        ws_manager.set_pubsub(pubsub)
        app.state.redis_pubsub = pubsub
    try:
        yield
    finally:
        manager = GameManager.get_instance()
        manager.close()
        pubsub = getattr(app.state, "redis_pubsub", None)
        if pubsub is not None:
            await pubsub.close()
        await close_db(app)


configure_logging()

app = FastAPI(title="RoboChess Backend", lifespan=lifespan)
app.include_router(api_router)
app.middleware("http")(request_logging_middleware())
