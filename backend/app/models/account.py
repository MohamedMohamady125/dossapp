from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, UniqueConstraint, Index
from sqlalchemy.sql import func
from app.database import Base


class Account(Base):
    __tablename__ = "accounts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    athlete_number = Column(Integer, nullable=False)
    login_code = Column(String(50), nullable=False, unique=True)
    password_hash = Column(String(255), nullable=False)
    must_change_password = Column(Boolean, default=True, nullable=False)
    name_at_creation = Column(String(300), nullable=False)
    dob_at_creation = Column(String(50), nullable=True)
    email = Column(String(255), nullable=True)
    phone_at_creation = Column(String(50), nullable=True)
    status = Column(String(30), default="active", nullable=False)  # active | disabled | identity_mismatch
    created_by_admin_id = Column(Integer, ForeignKey("admin_users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_login_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        UniqueConstraint("branch_id", "athlete_number", name="uq_account_branch_athlete"),
        Index("ix_account_branch_athlete", "branch_id", "athlete_number"),
        Index("ix_account_login_code", "login_code"),
    )
