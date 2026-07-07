from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, JSON, UniqueConstraint, Index
from sqlalchemy.sql import func
from app.database import Base


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False)
    token = Column(String(512), nullable=False, unique=True)
    platform = Column(String(10), nullable=False)  # android | ios
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_seen_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (Index("ix_device_tokens_account", "account_id"),)


class InboxNotification(Base):
    __tablename__ = "inbox_notifications"

    id = Column(Integer, primary_key=True, autoincrement=True)
    account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False)
    type = Column(String(30), nullable=False)  # schedule_change | payment_reminder | missed_sessions | test
    title = Column(String(200), nullable=False)
    body = Column(String(1000), nullable=False)
    data = Column(JSON, nullable=True)
    is_read = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (Index("ix_inbox_account_read", "account_id", "is_read"),)


class ScheduleSnapshot(Base):
    __tablename__ = "schedule_snapshots"

    id = Column(Integer, primary_key=True, autoincrement=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    athlete_number = Column(Integer, nullable=False)
    schedule_hash = Column(String(64), nullable=False)
    schedule_json = Column(JSON, nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (UniqueConstraint("branch_id", "athlete_number", name="uq_schedule_snapshot_branch_athlete"),)


class NotificationDedupe(Base):
    __tablename__ = "notification_dedupe"

    id = Column(Integer, primary_key=True, autoincrement=True)
    dedupe_key = Column(String(255), nullable=False, unique=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
