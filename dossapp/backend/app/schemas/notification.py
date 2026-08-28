from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class DeviceTokenIn(BaseModel):
    token: str
    platform: str  # android | ios
    language: str = "en"  # en | ar


class NotificationOut(BaseModel):
    id: int
    type: str
    title: str
    body: str
    data: Optional[dict] = None
    is_read: bool
    created_at: datetime


class UnreadCountOut(BaseModel):
    unread: int


class TestSendRequest(BaseModel):
    branch_id: int
    athlete_number: int
    title: str = "Test notification"
    body: str = "This is a test notification from Aquathletic."
    dry_run: bool = True
