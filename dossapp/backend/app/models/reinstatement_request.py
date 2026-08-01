from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Index
from sqlalchemy.sql import func
from app.database import Base


class ReinstatementRequest(Base):
    __tablename__ = "reinstatement_requests"

    id = Column(Integer, primary_key=True, autoincrement=True)
    account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    athlete_number = Column(Integer, nullable=False)
    status = Column(String(20), default="pending", nullable=False)  # pending | approved | declined
    message = Column(String(1000), nullable=True)  # user's message
    admin_note = Column(String(1000), nullable=True)  # admin response
    reviewed_by = Column(Integer, ForeignKey("admin_users.id"), nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        Index("ix_reinstatement_account_status", "account_id", "status"),
    )
