"""Pydantic v2 DTO cho Announcement & WatchSource."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict


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
