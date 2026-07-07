from pydantic import BaseModel
from typing import Optional


class CoachSession(BaseModel):
    day_pair: Optional[str] = None
    time_block: Optional[str] = None
    swimmers: list[str] = []


class CoachScheduleResponse(BaseModel):
    coach_name: str
    branch_name: str
    sessions: list[CoachSession] = []
