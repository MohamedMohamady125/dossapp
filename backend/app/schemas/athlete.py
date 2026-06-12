from pydantic import BaseModel
from typing import Optional
from decimal import Decimal


class ScheduleSlot(BaseModel):
    coach: Optional[str] = None
    time_block: Optional[str] = None
    day_pair: Optional[str] = None


class AthleteProfile(BaseModel):
    branch: str
    branch_id: int
    athlete_number: int
    name: str
    age: Optional[float] = None
    date_of_birth: Optional[str] = None
    gender: Optional[str] = None
    level: Optional[str] = None  # Step
    type: Optional[str] = None
    days: Optional[str] = None
    sessions: Optional[str] = None
    segment: Optional[str] = None  # f column
    schedule: list[ScheduleSlot] = []


class AthleteDetail(AthleteProfile):
    """Full detail for admin view — includes all Excel fields."""
    pay: Optional[str] = None
    phone1: Optional[str] = None
    phone2: Optional[str] = None
    comment: Optional[str] = None
    receipt_no: Optional[str] = None
    has_account: bool = False


class BillResponse(BaseModel):
    period: str
    amount_owed: Optional[str] = None
    is_paid: bool = False
    receipt_number: Optional[str] = None
    no_enrollment: bool = False
    # Store-acceptance framing: show branch, coach, class time
    branch_name: Optional[str] = None
    schedule: list[ScheduleSlot] = []


class ProvisionRequest(BaseModel):
    delivery_method: str = "in_person"  # "in_person" | "auto_send" | "both"


class ProvisionResponse(BaseModel):
    login_code: str
    temp_password: str
    delivery_method: str
    sent_to: Optional[str] = None
