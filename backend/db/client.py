from typing import Optional

from fastapi import FastAPI
from starlette.requests import HTTPConnection
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

from backend.core.config import load_settings
from backend.db.indexes import ensure_indexes


async def init_db(app: FastAPI) -> None:
    settings = load_settings()
    client = AsyncIOMotorClient(settings.mongodb_uri)
    db = client[settings.mongodb_db]
    app.state.mongo_client = client
    app.state.mongo_db = db
    await ensure_indexes(db)


async def close_db(app: FastAPI) -> None:
    client: Optional[AsyncIOMotorClient] = getattr(app.state, "mongo_client", None)
    if client is not None:
        client.close()
    app.state.mongo_client = None
    app.state.mongo_db = None


def get_db(conn: HTTPConnection) -> AsyncIOMotorDatabase:
    return conn.app.state.mongo_db
