"""Gom router v1."""

from fastapi import APIRouter

from app.api.v1 import announcements

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(announcements.router)
