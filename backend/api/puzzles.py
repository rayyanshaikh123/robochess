from fastapi import APIRouter, Depends

from backend.api.schemas import ApiResponse, PuzzleAttemptRequest
from backend.core.dependencies import get_current_user_id
from backend.db.client import get_db
from backend.services.puzzle_service import (
    attempt_puzzle_move,
    get_puzzle_detail,
    list_available_puzzles,
)
from backend.utils.helpers import error, ok

router = APIRouter()


@router.get("/list", response_model=ApiResponse)
async def list_puzzles(
    limit: int = 20,
    rating_min: int | None = None,
    rating_max: int | None = None,
    tag: str | None = None,
    db=Depends(get_db),
) -> ApiResponse:
    puzzles = await list_available_puzzles(
        db, limit=limit, rating_min=rating_min, rating_max=rating_max, tag=tag
    )
    return ok("ok", {"items": puzzles})


@router.get("/{puzzle_id}", response_model=ApiResponse)
async def puzzle_detail(puzzle_id: str, db=Depends(get_db)) -> ApiResponse:
    puzzle, err = await get_puzzle_detail(db, puzzle_id)
    if err:
        return error(err)
    return ok("ok", puzzle)


@router.post("/attempt", response_model=ApiResponse)
async def attempt(
    payload: PuzzleAttemptRequest,
    db=Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> ApiResponse:
    data, err = await attempt_puzzle_move(
        db, payload.puzzle_id, payload.uci, payload.move_index, user_id
    )
    if err:
        return error(err)
    return ok("ok", data)
