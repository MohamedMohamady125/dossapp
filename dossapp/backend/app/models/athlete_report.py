from sqlalchemy import Column, Integer, String, Text, ForeignKey, DateTime, LargeBinary, UniqueConstraint, Index
from sqlalchemy.orm import deferred
from sqlalchemy.sql import func
from app.database import Base


class AthleteReport(Base):
    """Monthly report for an athlete: an uploaded PDF, a written note, or both."""

    __tablename__ = "athlete_reports"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    athlete_number = Column(Integer, nullable=False)
    period = Column(String(10), nullable=False)  # e.g. '2026-09'

    # Legacy 1..5 ratings. No longer collected: new reports store 0 so the
    # columns stay NOT NULL and older app builds can still parse the payload.
    technique = Column(Integer, nullable=False, default=0)
    endurance = Column(Integer, nullable=False, default=0)
    commitment = Column(Integer, nullable=False, default=0)
    discipline = Column(Integer, nullable=False, default=0)

    coach_notes = Column(Text, nullable=True)  # the note

    # Uploaded PDF, kept in the database because the app server's disk is
    # wiped on every deploy. Deferred so list queries never load the bytes.
    pdf_filename = Column(String(255), nullable=True)
    pdf_data = deferred(Column(LargeBinary, nullable=True))
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
