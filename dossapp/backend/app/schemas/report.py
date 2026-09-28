"""Schemas for monthly athlete reports."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class ReportUpsert(BaseModel):
    branch_id: int
    athlete_number: int
    period: str = Field(..., description="YYYY-MM")
    technique: int = Field(..., ge=1, le=5)
    endurance: int = Field(..., ge=1, le=5)
    commitment: int = Field(..., ge=1, le=5)
    discipline: int = Field(..., ge=1, le=5)
    coach_notes: Optional[str] = Field(None, max_length=4000)
    goals: Optional[str] = Field(None, max_length=4000)

    @field_validator("period")
    @classmethod
    def valid_period(cls, v: str) -> str:
        parts = v.split("-")
        if len(parts) != 2 or len(parts[0]) != 4 or not parts[0].isdigit() or not parts[1].isdigit():
            raise ValueError("period must be YYYY-MM")
        month = int(parts[1])
        if month < 1 or month > 12:
            raise ValueError("period month must be 01-12")
        return f"{parts[0]}-{int(parts[1]):02d}"


class ReportOut(BaseModel):
    id: int
    branch_id: int
    athlete_number: int
    athlete_name: Optional[str] = None
    period: str
    technique: int
    endurance: int
    commitment: int
    discipline: int
    coach_notes: Optional[str]
    goals: Optional[str]
    created_by_name: str
    created_by_role: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ReportSwimmer(BaseModel):
    athlete_number: int
    name: str
    has_current_report: bool = False


class ReportSwimmersResponse(BaseModel):
    branch_id: int
    branch_name: str
    current_period: str
    swimmers: list[ReportSwimmer]
