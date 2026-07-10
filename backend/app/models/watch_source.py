"""Bảng watch_sources — whitelist nguồn GỐC chính thức để crawl.

Lưu selector/parser trong DB để đổi nguồn KHÔNG cần sửa code (giảm rủi ro parser vỡ).
"""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class WatchSource(Base):
    __tablename__ = "watch_sources"

    id: Mapped[int] = mapped_column(primary_key=True)
    topic: Mapped[str] = mapped_column(String(32), index=True)  # jlpt | mba | custom
    url: Mapped[str] = mapped_column(String(1024))
    # parser_type: "list" (quét item theo item_selector) | "page" (cả trang là 1 mục)
    parser_type: Mapped[str] = mapped_column(String(16), default="list")
    # CSS selector chọn từng mục tin (khi parser_type=list)
    item_selector: Mapped[str] = mapped_column(String(255), default="a")
    # từ khoá gợi ý khớp chủ đề (phân tách bởi |) — dùng cho rule-based fallback
    keywords: Mapped[str] = mapped_column(String(512), default="")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
