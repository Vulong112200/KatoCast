"""Cron entrypoint: crawl mọi nguồn 1 lần.

Chạy: python -m app.jobs.daily_crawl [topic]
Lịch bằng cron OS / Cloud Scheduler / GitHub Actions scheduled workflow.
"""

import asyncio
import sys

from app.db.session import async_session_factory
from app.services import crawl_service


async def _main(topic: str | None) -> None:
    async with async_session_factory() as session:
        new_count = await crawl_service.run_all(session, topic)
        print(f"[daily_crawl] topic={topic or 'all'} new={new_count}")


if __name__ == "__main__":
    topic_arg = sys.argv[1] if len(sys.argv) > 1 else None
    asyncio.run(_main(topic_arg))
