from sqlalchemy import Column, Integer, String, Text, ForeignKey, DateTime, UniqueConstraint, Index
from sqlalchemy.sql import func
from app.database import Base


class AthleteReport(Base):
    """Monthly performance report written by a coach/admin for an athlete."""

    __tablename__ = "athlete_reports"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    athlete_number = Column(Integer, nullable=False)
    period = Column(String(10), nullable=False)  # e.g. '2026-09'

    # Ratings 1..5
    technique = Column(Integer, nullable=False)
    endurance = Column(Integer, nullable=False)
    commitment = Column(Integer, nullable=False)
    discipline = Column(Integer, nullable=False)

    coach_notes = Column(Text, nullable=True)
    goals = Column(Text, nullable=True)  # focus for next month

    created_by_id = Column(Integer, ForeignKey("admin_users.id"), nullable=False)
    created_by_name = Column(String(200), nullable=False)
    created_by_role = Column(String(20), nullable=False)  # admin | assistant | coach
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint("branch_id", "athlete_number", "period", name="uq_report_branch_athlete_period"),
        Index("ix_report_branch_athlete", "branch_id", "athlete_number"),
    )
