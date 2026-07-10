"""LÕI: crawl whitelist nguồn → parse → diff (content_hash) → verify → lưu mục MỚI.

Chống fake: chỉ crawl các WatchSource (nguồn GỐC chính thức). source_domain lấy từ
URL nguồn nên notification luôn kèm domain kiểm chứng được.
"""

from __future__ import annotations

import hashlib
import json
import re
from urllib.parse import urljoin, urlparse

import httpx
from bs4 import BeautifulSoup

from app.core.config import get_settings
from app.models.announcement import Announcement
from app.models.watch_source import WatchSource
from app.repositories.announcement_repo import (
    AnnouncementRepository,
    WatchSourceRepository,
)
from app.services import date_extract, verify_service


def _normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def _hash(topic: str, title: str, url: str) -> str:
    key = f"{topic}|{_normalize(title)}|{url.strip()}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def _domain(url: str) -> str:
    return urlparse(url).netloc.lower()


class ParsedItem:
    def __init__(self, title: str, url: str, text: str) -> None:
        self.title = title
        self.url = url
        self.text = text


def _parse(source: WatchSource, html: bytes | str) -> list[ParsedItem]:
    # Truyền bytes để BeautifulSoup tự dò encoding (UTF-8/Shift-JIS...) → tránh mojibake.
    soup = BeautifulSoup(html, "html.parser")
    items: list[ParsedItem] = []
    if source.parser_type == "page":
        title = _normalize(soup.title.get_text() if soup.title else source.url)
        items.append(ParsedItem(title, source.url, _normalize(soup.get_text())))
        return items
    # parser_type == "list": mỗi phần tử khớp item_selector là 1 mục
    for el in soup.select(source.item_selector):
        title = _normalize(el.get_text())
        if not title:
            continue
        href = el.get("href") if el.has_attr("href") else None
        if not href:
            a = el.find("a", href=True)
            href = a["href"] if a else None
        url = urljoin(source.url, href) if href else source.url
        items.append(ParsedItem(title, url, title))
    return items


async def crawl_source(
    source: WatchSource,
    ann_repo: AnnouncementRepository,
    client: httpx.AsyncClient,
) -> list[Announcement]:
    """Crawl 1 nguồn, trả về các Announcement MỚI đã lưu."""
    resp = await client.get(source.url)
    resp.raise_for_status()
    parsed = _parse(source, resp.content)

    created: list[Announcement] = []
    for item in parsed:
        content_hash = _hash(source.topic, item.title, item.url)
        if await ann_repo.exists_by_hash(content_hash):
            continue  # đã thấy → không phải tin mới
        result = await verify_service.verify(
            source.topic, item.title, item.text, source.keywords
        )
        if not result.matched:
            continue  # không khớp chủ đề → bỏ
        dates = date_extract.extract_dates(item.text)
        ann = Announcement(
            topic=source.topic,
            title=item.title[:512],
            summary=result.summary,
            source_url=item.url[:1024],
            source_domain=_domain(item.url)[:255],
            content_hash=content_hash,
            verified=result.score >= 0.5,
            score=result.score,
            extracted_dates=json.dumps(dates, ensure_ascii=False) if dates else None,
        )
        await ann_repo.create(ann)
        created.append(ann)
    return created


async def run_all(session, topic: str | None = None) -> int:
    """Crawl mọi nguồn enabled (lọc theo topic nếu có). Trả số mục mới."""
    settings = get_settings()
    src_repo = WatchSourceRepository(session)
    ann_repo = AnnouncementRepository(session)
    sources = await src_repo.list_enabled(topic)

    total_new = 0
    headers = {"User-Agent": settings.crawl_user_agent}
    async with httpx.AsyncClient(
        headers=headers, timeout=20.0, follow_redirects=True
    ) as client:
        for source in sources:
            try:
                created = await crawl_source(source, ann_repo, client)
                total_new += len(created)
            except Exception:
                # 1 nguồn lỗi không được làm hỏng cả job
                continue
    await session.commit()
    return total_new
