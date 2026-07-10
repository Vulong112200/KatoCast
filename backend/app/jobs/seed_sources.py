"""Seed whitelist nguồn GỐC chính thức (idempotent theo url+topic).

Chạy: python -m app.jobs.seed_sources
JLPT: trang chính thức. MBA: thêm nguồn trường của bạn qua POST /watch-sources
hoặc bổ sung vào danh sách bên dưới.
"""

import asyncio

from sqlalchemy import select

from app.db.session import async_session_factory
from app.models.watch_source import WatchSource

_SEED: list[dict] = [
    # JLPT — nguồn chính thức
    {
        "topic": "jlpt",
        "url": "https://www.jlpt.jp/e/",
        "parser_type": "list",
        "item_selector": "a",
        "keywords": "test|application|schedule|registration|result",
    },
    {
        "topic": "jlpt",
        "url": "https://info.jees-jlpt.jp/",
        "parser_type": "list",
        "item_selector": "a",
        "keywords": "出願|申込|試験|受験案内",
    },
    # MBA — nguồn tuyển sinh CHÍNH THỨC là theo từng trường bạn quan tâm. Thêm
    # trang admissions của trường bạn qua POST /api/v1/watch-sources hoặc bổ sung
    # vào đây. Ví dụ mẫu (đổi URL/selector cho khớp trang thật của bạn):
    # {
    #     "topic": "mba",
    #     "url": "https://<truong-cua-ban>/admissions/mba",
    #     "parser_type": "list",
    #     "item_selector": "a",
    #     "keywords": "mba|admission|tuyển sinh|gmat|deadline|募集",
    # },
]


async def _main() -> None:
    async with async_session_factory() as session:
        added = 0
        for row in _SEED:
            exists = (
                await session.execute(
                    select(WatchSource.id).where(
                        WatchSource.url == row["url"],
                        WatchSource.topic == row["topic"],
                    )
                )
            ).first()
            if exists:
                continue
            session.add(WatchSource(**row))
            added += 1
        await session.commit()
        print(f"[seed_sources] added={added}")


if __name__ == "__main__":
    asyncio.run(_main())
