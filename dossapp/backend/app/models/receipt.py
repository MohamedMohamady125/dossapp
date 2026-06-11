from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, LargeBinary, JSON
from sqlalchemy.sql import func
from app.database import Base


class Receipt(Base):
    __tablename__ = "receipts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    payment_id = Column(Integer, ForeignKey("payments.id"), nullable=False, unique=True)
    receipt_number = Column(String(50), nullable=False, unique=True)  # P-000123 or C-<excel_no>
    pdf_data = Column(LargeBinary, nullable=True)
    issued_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    # Snapshot fields for re-rendering
    athlete_name = Column(String(300), nullable=False)
    athlete_number = Column(Integer, nullable=False)
    branch_name = Column(String(200), nullable=False)
    level = Column(String(100), nullable=True)
    athlete_type = Column(String(100), nullable=True)
    phone = Column(String(50), nullable=True)
    period = Column(String(10), nullable=False)
    amount_paid = Column(String(20), nullable=False)
    payment_channel = Column(String(20), nullable=False)  # Online | Cash
    paymob_transaction_id = Column(String(100), nullable=True)

    send_status = Column(JSON, default=dict, nullable=False)
    # e.g. {"sms": "sent", "email": "pending", "whatsapp": "failed"}
