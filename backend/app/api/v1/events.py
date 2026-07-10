"""Routing exam-events (lịch có cấu trúc). Chỉ validation + gọi repo."""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_session
from app.repositories.exam_event_repo import ExamEventRepository
from app.schemas.exam_event import ExamEventRead

router = APIRouter(tags=["events"])


@router.get("/events", response_model=list[ExamEventRead])
async def list_events(
    topic: str | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
) -> list[ExamEventRead]:
    repo = ExamEventRepository(session)
    rows = await repo.list(topic)
    return [ExamEventRead.model_validate(r) for r in rows]
