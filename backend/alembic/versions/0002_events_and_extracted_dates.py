"""events + extracted_dates

Revision ID: 0002
Revises: 0001
Create Date: 2026-07-10
"""
from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "exam_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("topic", sa.String(length=32), nullable=False),
        sa.Column("session_label", sa.String(length=255), nullable=False),
        sa.Column("registration_start", sa.Date(), nullable=True),
        sa.Column("registration_end", sa.Date(), nullable=True),
        sa.Column("exam_date", sa.Date(), nullable=True),
        sa.Column("result_date", sa.Date(), nullable=True),
        sa.Column("source_url", sa.String(length=1024), nullable=False, server_default=""),
        sa.Column("source_domain", sa.String(length=255), nullable=False, server_default=""),
        sa.Column("curated", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("note", sa.Text(), nullable=False, server_default=""),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_exam_events_topic", "exam_events", ["topic"])
    op.create_index("ix_exam_events_source_domain", "exam_events", ["source_domain"])

    op.add_column(
        "announcements",
        sa.Column("extracted_dates", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("announcements", "extracted_dates")
    op.drop_table("exam_events")
