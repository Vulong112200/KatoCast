"""Cấu hình tập trung (đọc từ env / .env). Pydantic v2 settings."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    database_url: str = "sqlite+aiosqlite:///./katoassistant.db"
    anthropic_api_key: str = ""
    verify_model: str = "claude-haiku-4-5-20251001"
    cors_origins: str = "*"
    crawl_user_agent: str = "KatoAssistant/1.0 (+https://github.com/VuhpAlx)"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def has_llm(self) -> bool:
        return bool(self.anthropic_api_key.strip())


@lru_cache
def get_settings() -> Settings:
    return Settings()
