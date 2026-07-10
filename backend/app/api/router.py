"""Gom router v1."""

from fastapi import APIRouter

from app.api.v1 import announcements, events

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(announcements.router)
api_router.include_router(events.router)
