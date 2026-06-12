"""RosterSource interface — the migration seam.

Currently backed by Excel files on Google Drive.
Replace the implementation to swap for a DB-backed source.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ScheduleEntry:
    coach: Optional[str] = None
    time_block: Optional[str] = None
    day_pair: Optional[str] = None


@dataclass
class Athlete:
    branch: str
    branch_id: int
    athlete_number: int
    name: str
    date_of_birth: Optional[str] = None
    age_computed: Optional[float] = None
    gender: Optional[str] = None
    step: Optional[str] = None  # level
    type: Optional[str] = None
    days: Optional[str] = None
    sessions: Optional[str] = None
    pay: Optional[str] = None
    phone1: Optional[str] = None
    phone2: Optional[str] = None
    segment: Optional[str] = None  # f column
    comment: Optional[str] = None
    receipt_no: Optional[str] = None
    schedule: list[ScheduleEntry] = field(default_factory=list)


@dataclass
class BranchRoster:
    branch_id: int
    branch_name: str
    athletes: list[Athlete]
    coaches: list[str]
    price_matrix: dict  # reference only
    parse_errors: list[str] = field(default_factory=list)
    last_modified: Optional[str] = None
    last_refreshed: Optional[str] = None
    period: Optional[str] = None  # Tier 3: stamp with billing period (YYYY-MM)


class RosterSource(ABC):
    """Interface for reading athlete rosters. Excel implementation below; swap for DB later."""

    @abstractmethod
    async def get_branch_roster(self, branch_id: int) -> Optional[BranchRoster]:
        ...

    @abstractmethod
    async def get_all_rosters(self) -> dict[int, BranchRoster]:
        ...

    @abstractmethod
    async def refresh_branch(self, branch_id: int) -> bool:
        """Re-read source for this branch. Returns True if data changed."""
        ...

    @abstractmethod
    async def refresh_all(self) -> dict[int, bool]:
        ...

    @abstractmethod
    def get_health(self) -> dict:
        """Per-branch parse status for the health endpoint."""
        ...
