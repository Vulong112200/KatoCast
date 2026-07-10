"""Data access cho Announcement & WatchSource. CHỈ truy vấn, không business logic."""

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.announcement import Announcement
from app.models.watch_source import WatchSource


class AnnouncementRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def exists_by_hash(self, content_hash: str) -> bool:
        stmt = select(Announcement.id).where(Announcement.content_hash == content_hash)
        return (await self.session.execute(stmt)).first() is not None

    async def create(self, ann: Announcement) -> Announcement:
        self.session.add(ann)
        await self.session.flush()
        return ann

    async def list_since(
        self, topic: str | None, since: datetime | None, limit: int = 100
    ) -> list[Announcement]:
        stmt = select(Announcement).order_by(Announcement.first_seen_at.desc())
        if topic:
            stmt = stmt.where(Announcement.topic == topic)
        if since:
            stmt = stmt.where(Announcement.first_seen_at > since)
        stmt = stmt.limit(limit)
        return list((await self.session.execute(stmt)).scalars().all())


class WatchSourceRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list_enabled(self, topic: str | None = None) -> list[WatchSource]:
        stmt = select(WatchSource).where(WatchSource.enabled.is_(True))
        if topic:
            stmt = stmt.where(WatchSource.topic == topic)
        return list((await self.session.execute(stmt)).scalars().all())

    async def list_all(self) -> list[WatchSource]:
        stmt = select(WatchSource).order_by(WatchSource.id)
        return list((await self.session.execute(stmt)).scalars().all())

    async def create(self, src: WatchSource) -> WatchSource:
        self.session.add(src)
        await self.session.flush()
        return src
