"""Seed lịch CHUẨN (curated) cho kỳ thi có lịch cố định. Idempotent theo
(topic, session_label) — chạy lại an toàn, tự cập nhật nếu ngày đổi.

Chạy: python -m app.jobs.seed_events

⚠️ Ngày dưới đây ĐÃ xác thực từ nguồn chính thức JEES (info.jees-jlpt.jp) —
lịch thi TẠI NHẬT. Thí sinh ở nước ngoài có thể khác; khi bổ sung phải kiểm
chứng lại từ trang chính thức trước khi seed. KHÔNG đoán ngày.
"""

import asyncio
from datetime import date

from app.db.session import async_session_factory
from app.repositories.exam_event_repo import ExamEventRepository

_JLPT_SRC = "https://info.jees-jlpt.jp/"
_JLPT_DOMAIN = "info.jees-jlpt.jp"

# Nguồn: info.jees-jlpt.jp/info/2026-1jisshiannai.html & 2026-2jisshiannnai.html
_SEED: list[dict] = [
    {
        "topic": "jlpt",
        "session_label": "JLPT Kỳ 1/2026 (Tháng 7) — tại Nhật",
        "registration_start": date(2026, 3, 17),
        "registration_end": date(2026, 4, 7),
        "exam_date": date(2026, 7, 5),
        "result_date": None,  # phân phối cuối 9/2026; xem điểm MyJLPT cuối 8/2026
        "source_url": "https://info.jees-jlpt.jp/info/2026-1jisshiannai.html",
        "source_domain": _JLPT_DOMAIN,
        "curated": True,
        "note": "Lịch thi tại Nhật (JEES). Kết quả: cuối 9/2026 (xem điểm MyJLPT từ cuối 8/2026). Nước ngoài có thể khác.",
    },
    {
        "topic": "jlpt",
        "session_label": "JLPT Kỳ 2/2026 (Tháng 12) — tại Nhật",
        "registration_start": date(2026, 8, 17),
        "registration_end": date(2026, 9, 7),
        "exam_date": date(2026, 12, 6),
        "result_date": None,  # phân phối cuối 2/2027; xem điểm MyJLPT cuối 1/2027
        "source_url": "https://info.jees-jlpt.jp/info/2026-2jisshiannnai.html",
        "source_domain": _JLPT_DOMAIN,
        "curated": True,
        "note": "Lịch thi tại Nhật (JEES). Kết quả: cuối 2/2027 (xem điểm MyJLPT từ cuối 1/2027). Nước ngoài có thể khác.",
    },
    # MBA: lịch theo từng trường → người dùng tự thêm/nhập tay trong app.
]


async def _main() -> None:
    async with async_session_factory() as session:
        repo = ExamEventRepository(session)
        created = updated = 0
        for row in _SEED:
            _, is_new = await repo.upsert_by_label(row)
            created += int(is_new)
            updated += int(not is_new)
        await session.commit()
        print(f"[seed_events] created={created} updated={updated}")


if __name__ == "__main__":
    asyncio.run(_main())
