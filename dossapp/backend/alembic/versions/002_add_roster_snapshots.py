"""Add roster_snapshots table for Tier 3 analytics

Revision ID: 002
Revises: 001
Create Date: 2026-06-01
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "roster_snapshots",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("branch_id", sa.Integer(), nullable=False),
        sa.Column("period", sa.String(10), nullable=False),
        sa.Column("snapshot_data", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_snapshot_branch_period", "roster_snapshots", ["branch_id", "period"])


def downgrade() -> None:
    op.drop_table("roster_snapshots")
