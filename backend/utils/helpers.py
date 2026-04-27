from typing import Any, Optional


def ok(message: str = "ok", data: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    return {"status": "ok", "message": message, "data": data}


def error(message: str, data: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    return {"status": "error", "message": message, "data": data}
