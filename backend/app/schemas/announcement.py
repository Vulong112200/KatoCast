"""Pydantic v2 DTO cho Announcement & WatchSource."""

import json
from datetime import datetime

from pydantic import BaseModel, ConfigDict, field_validator


class ExtractedDate(BaseModel):
    date: str          # ISO YYYY-MM-DD
    label: str         # registration | exam | deadline | result | unknown
    raw: str = ""


class AnnouncementRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    topic: str
    title: str
    summary: str
    source_url: str
    source_domain: str
    published_at: datetime | None
    first_seen_at: datetime
    content_hash: str
    verified: bool
    score: float
    # ngày tự phát hiện (chưa kiểm chứng); DB lưu JSON string → parse thành list
    extracted_dates: list[ExtractedDate] = []

    @field_validator("extracted_dates", mode="before")
    @classmethod
    def _parse_extracted(cls, v):
        if v is None or v == "":
            return []
        if isinstance(v, str):
            try:
                return json.loads(v)
            except (ValueError, TypeError):
                return []
        return v


class WatchSourceCreate(BaseModel):
    topic: str
    url: str
    parser_type: str = "list"
    item_selector: str = "a"
    keywords: str = ""
    enabled: bool = True


class WatchSourceRead(WatchSourceCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
