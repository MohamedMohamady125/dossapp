from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Boolean
from sqlalchemy.sql import func
from app.database import Base


class EmailVerification(Base):
    __tablename__ = "email_verifications"

    id = Column(Integer, primary_key=True, autoincrement=True)
    account_id = Column(Integer, ForeignKey("accounts.id"), nullable=True)  # null for forgot-password by login_code
    email = Column(String(255), nullable=False)
    code = Column(String(6), nullable=False)  # 6-digit code
    purpose = Column(String(20), nullable=False)  # "onboarding" | "forgot_password"
    verified = Column(Boolean, default=False)
    attempts = Column(Integer, default=0)  # track failed attempts
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=False)
