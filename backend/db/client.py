from typing import Optional
from urllib.parse import parse_qs, urlparse

from fastapi import FastAPI
from starlette.requests import HTTPConnection
import certifi
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

from backend.core.config import load_settings
from backend.db.indexes import ensure_indexes


def _requires_tls(mongodb_uri: str) -> bool:
    if mongodb_uri.startswith("mongodb+srv://"):
        return True
    parsed = urlparse(mongodb_uri)
    query = parse_qs(parsed.query)
    tls_values = query.get("tls") or query.get("ssl")
    if not tls_values:
        return False
    return tls_values[-1].lower() in {"true", "1", "yes"}


async def init_db(app: FastAPI) -> None:
    settings = load_settings()
    client_kwargs = {
        "connectTimeoutMS": settings.mongodb_connect_timeout_ms,
        "socketTimeoutMS": settings.mongodb_socket_timeout_ms,
        "serverSelectionTimeoutMS": settings.mongodb_server_selection_timeout_ms,
    }
    if _requires_tls(settings.mongodb_uri):
        client_kwargs["tls"] = True
        client_kwargs["tlsCAFile"] = certifi.where()
    client = AsyncIOMotorClient(settings.mongodb_uri, **client_kwargs)
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
