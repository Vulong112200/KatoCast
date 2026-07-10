"""Routing announcements + watch-sources. Chỉ validation + gọi repo/service."""

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_session
from app.models.watch_source import WatchSource
from app.repositories.announcement_repo import (
    AnnouncementRepository,
    WatchSourceRepository,
)
from app.schemas.announcement import (
    AnnouncementRead,
    WatchSourceCreate,
    WatchSourceRead,
)
from app.services import crawl_service

router = APIRouter(tags=["announcements"])


@router.get("/announcements", response_model=list[AnnouncementRead])
async def list_announcements(
    topic: str | None = Query(default=None),
    since: datetime | None = Query(default=None, description="ISO8601; lọc first_seen_at >"),
    limit: int = Query(default=100, le=500),
    session: AsyncSession = Depends(get_session),
) -> list[AnnouncementRead]:
    repo = AnnouncementRepository(session)
    rows = await repo.list_since(topic, since, limit)
    return [AnnouncementRead.model_validate(r) for r in rows]


@router.get("/watch-sources", response_model=list[WatchSourceRead])
async def list_watch_sources(
    session: AsyncSession = Depends(get_session),
) -> list[WatchSourceRead]:
    repo = WatchSourceRepository(session)
    rows = await repo.list_all()
    return [WatchSourceRead.model_validate(r) for r in rows]


@router.post("/watch-sources", response_model=WatchSourceRead, status_code=201)
async def create_watch_source(
    payload: WatchSourceCreate,
    session: AsyncSession = Depends(get_session),
) -> WatchSourceRead:
    repo = WatchSourceRepository(session)
    src = await repo.create(WatchSource(**payload.model_dump()))
    await session.commit()
    return WatchSourceRead.model_validate(src)


@router.post("/crawl")
async def trigger_crawl(
    topic: str | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Chạy crawl ngay (tiện test / cron gọi qua HTTP). Trả số mục mới."""
    new_count = await crawl_service.run_all(session, topic)
    return {"new": new_count}
