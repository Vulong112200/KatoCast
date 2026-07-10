"""Test diff/dedup của crawl_service với HTML fixture cố định (không mạng)."""

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.db.base import Base
from app.models.announcement import Announcement
from app.models.watch_source import WatchSource
from app.repositories.announcement_repo import AnnouncementRepository
from app.services import crawl_service

_HTML = """
<html><body>
  <a href="/e/2026/news1.html">2026年度 第2回 日本語能力試験 出願受付開始 12月</a>
  <a href="/e/about.html">このサイトについて</a>
  <a href="/e/2026/news2.html">試験結果発表 申込 スケジュール 2026/09/01</a>
</body></html>
"""


class _FakeResp:
    def __init__(self, text: str) -> None:
        self.text = text
        self.content = text.encode("utf-8")

    def raise_for_status(self) -> None:
        pass


class _FakeClient:
    def __init__(self, text: str) -> None:
        self._text = text

    async def get(self, url: str) -> _FakeResp:
        return _FakeResp(self._text)


@pytest_asyncio.fixture
async def session() -> AsyncSession:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as s:
        yield s


@pytest.mark.asyncio
async def test_diff_dedup(session: AsyncSession) -> None:
    src = WatchSource(
        topic="jlpt", url="https://www.jlpt.jp/e/",
        parser_type="list", item_selector="a", keywords="出願|申込|試験",
    )
    ann_repo = AnnouncementRepository(session)
    client = _FakeClient(_HTML)

    # lần 1: các mục khớp chủ đề (có keyword) được tạo, mục "このサイトについて" bị loại
    created1 = await crawl_service.crawl_source(src, ann_repo, client)
    await session.commit()
    titles = [a.title for a in created1]
    assert any("出願" in t for t in titles)
    assert all("このサイトについて" not in t for t in titles)
    assert len(created1) == 2

    # lần 2: cùng HTML → không có mục MỚI (dedup theo content_hash)
    created2 = await crawl_service.crawl_source(src, ann_repo, client)
    await session.commit()
    assert created2 == []
