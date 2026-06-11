"""Tier 3 plumbing — period-stamped roster snapshots for future trend analytics."""

from sqlalchemy import Column, Integer, String, DateTime, JSON
from sqlalchemy.sql import func
from app.database import Base


class RosterSnapshot(Base):
    __tablename__ = "roster_snapshots"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, nullable=False)
    period = Column(String(10), nullable=False)  # e.g. '2026-06'
    snapshot_data = Column(JSON, nullable=False)
    # snapshot_data contains: {total_athletes, enrollment_by_level, enrollment_by_type,
    #   segment_mix, gender_split, age_stats, coach_load}
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    # One snapshot per branch per period
    __table_args__ = (
        # Allow multiple snapshots per period (latest wins) but index for fast lookup
        # Index("ix_snapshot_branch_period", "branch_id", "period"),
    )
