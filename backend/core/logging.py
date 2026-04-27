import logging
import time
from typing import Callable
from uuid import uuid4

from fastapi import Request, Response

from backend.core.config import load_settings


def configure_logging() -> None:
    settings = load_settings()
    level = settings.log_level.upper()
    logging.basicConfig(
        level=level,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )


def request_logging_middleware() -> Callable:
    logger = logging.getLogger("robochess.http")

    async def middleware(request: Request, call_next) -> Response:
        request_id = request.headers.get("X-Request-ID", str(uuid4()))
        start = time.perf_counter()
        response: Response | None = None
        try:
            response = await call_next(request)
        except Exception:
            duration_ms = (time.perf_counter() - start) * 1000
            logger.exception(
                "%s %s %s %.2fms request_id=%s",
                request.method,
                request.url.path,
                "ERR",
                duration_ms,
                request_id,
            )
            raise
        else:
            duration_ms = (time.perf_counter() - start) * 1000
            logger.info(
                "%s %s %s %.2fms request_id=%s",
                request.method,
                request.url.path,
                response.status_code,
                duration_ms,
                request_id,
            )
            response.headers["X-Request-ID"] = request_id
            return response

    return middleware
