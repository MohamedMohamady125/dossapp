from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class PaymentIntentResponse(BaseModel):
    token: str
    amount: str
    currency: str = "EGP"


class PaymentOut(BaseModel):
    id: int
    branch_id: int
    athlete_number: int
    athlete_name: str = ""
    level: Optional[str] = None
    athlete_type: Optional[str] = None
    period: str
    source: str
    amount_paid: str
    status: str
    paid_at: Optional[datetime] = None


class ReceiptOut(BaseModel):
    id: int
    receipt_number: str
    period: str
    amount_paid: str
    payment_channel: str
    issued_at: datetime
    athlete_name: str
    branch_name: str
    level: Optional[str] = None
    pdf_available: bool = False


class AnalyticsRequest(BaseModel):
    scope: str = "branch"  # "branch" | "academy"
    branch_id: Optional[int] = None
    period: Optional[str] = None
