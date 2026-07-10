"""KatoAssistant backend — FastAPI entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings
from app.db.base import Base
from app.db.session import engine
from app.models import Announcement, WatchSource  # noqa: F401 (register metadata)

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Dev tiện lợi: tạo bảng nếu chưa có (prod dùng Alembic migrate).
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(title="KatoAssistant API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "llm": settings.has_llm}
