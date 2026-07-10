"""Pydantic v2 DTO cho ExamEvent (lịch có cấu trúc)."""

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class ExamEventCreate(BaseModel):
    topic: str
    session_label: str
    registration_start: date | None = None
    registration_end: date | None = None
    exam_date: date | None = None
    result_date: date | None = None
    source_url: str = ""
    source_domain: str = ""
    curated: bool = False
    note: str = ""


class ExamEventRead(ExamEventCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int
    updated_at: datetime
