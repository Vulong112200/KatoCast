"""Import mọi model để Alembic autogenerate & Base.metadata thấy đủ bảng."""

from app.models.announcement import Announcement  # noqa: F401
from app.models.exam_event import ExamEvent  # noqa: F401
from app.models.watch_source import WatchSource  # noqa: F401
