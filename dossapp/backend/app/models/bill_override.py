from sqlalchemy import Column, Integer, Numeric, String, DateTime, UniqueConstraint
from sqlalchemy.sql import func
from app.database import Base


class BillOverride(Base):
    __tablename__ = "bill_overrides"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, nullable=False)
    athlete_number = Column(Integer, nullable=False)
    amount = Column(Numeric(10, 2), nullable=False)
    set_by_admin_id = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("branch_id", "athlete_number", name="uq_bill_override_branch_athlete"),
    )
