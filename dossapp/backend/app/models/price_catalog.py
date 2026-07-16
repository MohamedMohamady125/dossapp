from sqlalchemy import Column, Integer, String, ForeignKey, Numeric, Boolean, DateTime, UniqueConstraint, Index
from sqlalchemy.sql import func

from app.database import Base


class PriceCatalog(Base):
    __tablename__ = "price_catalog"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    program_name = Column(String(100), nullable=False)
    segment = Column(String(50), nullable=True)   # "Student" | "Outsider" | NULL (= all)
    sessions = Column(String(50), nullable=True)   # "1 Session" | "8 Sessions" | NULL (= monthly)
    price = Column(Numeric(12, 2), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("branch_id", "program_name", "segment", "sessions", name="uq_price_catalog_entry"),
        Index("ix_price_catalog_branch", "branch_id"),
    )
