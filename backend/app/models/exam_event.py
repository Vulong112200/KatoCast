"""Bảng exam_events — lịch CÓ CẤU TRÚC của kỳ thi/đợt tuyển sinh.

Đây là nguồn sự thật cho "thời hạn năm nay". curated=True nghĩa là lịch chuẩn đã
seed/kiểm chứng thủ công từ nguồn chính thức (chính xác cao). Trạng thái còn hạn/
hết hạn KHÔNG lưu ở đây — client tự tính so với now để luôn tươi.
"""

from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ExamEvent(Base):
    __tablename__ = "exam_events"

    id: Mapped[int] = mapped_column(primary_key=True)
    topic: Mapped[str] = mapped_column(String(32), index=True)  # jlpt | mba | custom
    session_label: Mapped[str] = mapped_column(String(255))  # "JLPT Kỳ 7/2026"
    registration_start: Mapped[date | None] = mapped_column(Date, nullable=True)
    registration_end: Mapped[date | None] = mapped_column(Date, nullable=True)
    exam_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    result_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    source_url: Mapped[str] = mapped_column(String(1024), default="")
    source_domain: Mapped[str] = mapped_column(String(255), default="", index=True)
    curated: Mapped[bool] = mapped_column(Boolean, default=False)
    note: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
