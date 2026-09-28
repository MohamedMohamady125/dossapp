"""Add athlete_reports table for monthly coach reports

Revision ID: 003
Revises: 002
Create Date: 2026-09-28
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "athlete_reports",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("branch_id", sa.Integer(), sa.ForeignKey("branches.id"), nullable=False),
        sa.Column("athlete_number", sa.Integer(), nullable=False),
        sa.Column("period", sa.String(10), nullable=False),
        sa.Column("technique", sa.Integer(), nullable=False),
        sa.Column("endurance", sa.Integer(), nullable=False),
        sa.Column("commitment", sa.Integer(), nullable=False),
        sa.Column("discipline", sa.Integer(), nullable=False),
        sa.Column("coach_notes", sa.Text(), nullable=True),
        sa.Column("goals", sa.Text(), nullable=True),
        sa.Column("created_by_id", sa.Integer(), sa.ForeignKey("admin_users.id"), nullable=False),
        sa.Column("created_by_name", sa.String(200), nullable=False),
        sa.Column("created_by_role", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("branch_id", "athlete_number", "period", name="uq_report_branch_athlete_period"),
    )
    op.create_index("ix_report_branch_athlete", "athlete_reports", ["branch_id", "athlete_number"])


def downgrade() -> None:
    op.drop_table("athlete_reports")
