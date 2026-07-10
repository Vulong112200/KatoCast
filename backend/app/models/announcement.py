"""Bảng announcements — mỗi thông báo (đã diff & xác thực) từ nguồn chính thức."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Announcement(Base):
    __tablename__ = "announcements"

    id: Mapped[int] = mapped_column(primary_key=True)
    topic: Mapped[str] = mapped_column(String(32), index=True)  # jlpt | mba | custom
    title: Mapped[str] = mapped_column(String(512))
    summary: Mapped[str] = mapped_column(Text, default="")
    source_url: Mapped[str] = mapped_column(String(1024))
    source_domain: Mapped[str] = mapped_column(String(255), index=True)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
    # hash nội dung chuẩn hoá — dedup, phát hiện mục MỚI
    content_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    score: Mapped[float] = mapped_column(Float, default=0.0)  # độ khớp chủ đề 0..1
    # ngày regex tự phát hiện trong tin (JSON list [{date, label, raw}]) — GỢI Ý,
    # chưa kiểm chứng. Lịch chuẩn nằm ở exam_events.
    extracted_dates: Mapped[str | None] = mapped_column(Text, nullable=True)
