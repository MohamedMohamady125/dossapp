from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Numeric, UniqueConstraint, Index
from sqlalchemy.sql import func
from app.database import Base


class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    athlete_number = Column(Integer, nullable=False)
    period = Column(String(10), nullable=False)  # e.g. '2026-06'
    source = Column(String(20), nullable=False)  # 'paymob' | 'cash'
    amount_owed_snapshot = Column(Numeric(12, 2), nullable=True)
    amount_paid = Column(Numeric(12, 2), nullable=False)
    currency = Column(String(5), default="EGP", nullable=False)
    paymob_transaction_id = Column(String(100), nullable=True)
    excel_receipt_no = Column(String(100), nullable=True)
    status = Column(String(20), default="pending", nullable=False)  # pending | paid | failed | refunded
    paid_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint("branch_id", "athlete_number", "period", "source", name="uq_payment_idempotent"),
        Index("ix_payment_branch_athlete", "branch_id", "athlete_number"),
        Index("ix_payment_period", "period"),
        Index("ix_payment_status", "status"),
    )
