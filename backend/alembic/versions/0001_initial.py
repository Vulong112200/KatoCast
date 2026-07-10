"""initial: announcements + watch_sources

Revision ID: 0001
Revises:
Create Date: 2026-07-10
"""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "watch_sources",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("topic", sa.String(length=32), nullable=False),
        sa.Column("url", sa.String(length=1024), nullable=False),
        sa.Column("parser_type", sa.String(length=16), nullable=False, server_default="list"),
        sa.Column("item_selector", sa.String(length=255), nullable=False, server_default="a"),
        sa.Column("keywords", sa.String(length=512), nullable=False, server_default=""),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_watch_sources_topic", "watch_sources", ["topic"])

    op.create_table(
        "announcements",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("topic", sa.String(length=32), nullable=False),
        sa.Column("title", sa.String(length=512), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False, server_default=""),
        sa.Column("source_url", sa.String(length=1024), nullable=False),
        sa.Column("source_domain", sa.String(length=255), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("verified", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("score", sa.Float(), nullable=False, server_default="0"),
    )
    op.create_index("ix_announcements_topic", "announcements", ["topic"])
    op.create_index("ix_announcements_source_domain", "announcements", ["source_domain"])
    op.create_index("ix_announcements_first_seen_at", "announcements", ["first_seen_at"])
    op.create_index(
        "ix_announcements_content_hash", "announcements", ["content_hash"], unique=True
    )


def downgrade() -> None:
    op.drop_table("announcements")
    op.drop_table("watch_sources")
