"""Data access cho ExamEvent. CHỈ truy vấn, không business logic."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.exam_event import ExamEvent


class ExamEventRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list(self, topic: str | None = None) -> list[ExamEvent]:
        stmt = select(ExamEvent).order_by(ExamEvent.exam_date.desc().nullslast())
        if topic:
            stmt = stmt.where(ExamEvent.topic == topic)
        return list((await self.session.execute(stmt)).scalars().all())

    async def get_by_label(self, topic: str, session_label: str) -> ExamEvent | None:
        stmt = select(ExamEvent).where(
            ExamEvent.topic == topic,
            ExamEvent.session_label == session_label,
        )
        return (await self.session.execute(stmt)).scalars().first()

    async def upsert_by_label(self, data: dict) -> tuple[ExamEvent, bool]:
        """Tạo mới hoặc cập nhật theo (topic, session_label). Trả (event, created)."""
        existing = await self.get_by_label(data["topic"], data["session_label"])
        if existing:
            for k, v in data.items():
                setattr(existing, k, v)
            await self.session.flush()
            return existing, False
        ev = ExamEvent(**data)
        self.session.add(ev)
        await self.session.flush()
        return ev, True
