"""Tier 3 plumbing — save period-stamped roster snapshots for future trend analytics."""

import logging
from datetime import datetime
from decimal import Decimal, InvalidOperation

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.roster_snapshot import RosterSnapshot
from app.services.roster_source import BranchRoster

logger = logging.getLogger(__name__)


async def save_roster_snapshot(roster: BranchRoster, db: AsyncSession):
    """Save a snapshot of the current roster for this branch+period.

    Only saves once per branch per period (checks for existing).
    """
    period = roster.period or datetime.now().strftime("%Y-%m")

    # Check if we already have a snapshot for this branch+period today
    result = await db.execute(
        select(RosterSnapshot).where(
            RosterSnapshot.branch_id == roster.branch_id,
            RosterSnapshot.period == period,
        ).order_by(RosterSnapshot.created_at.desc()).limit(1)
    )
    existing = result.scalar_one_or_none()

    # Only save once per day per branch (not every refresh cycle)
    if existing:
        existing_date = existing.created_at.strftime("%Y-%m-%d") if existing.created_at else None
        today = datetime.now().strftime("%Y-%m-%d")
        if existing_date == today:
            return  # Already snapshot today

    # Build snapshot data
    level_counts: dict[str, int] = {}
    type_counts: dict[str, int] = {}
    segment_counts: dict[str, int] = {}
    gender_counts: dict[str, int] = {}
    ages: list[float] = []
    coach_load: dict[str, int] = {}

    for a in roster.athletes:
        level = a.step or "Unknown"
        level_counts[level] = level_counts.get(level, 0) + 1

        atype = a.type or "Unknown"
        type_counts[atype] = type_counts.get(atype, 0) + 1

        seg = a.segment or "Unknown"
        segment_counts[seg] = segment_counts.get(seg, 0) + 1

        g = a.gender or "Unknown"
        gender_counts[g] = gender_counts.get(g, 0) + 1

        if a.age_computed and a.age_computed < 100:
            ages.append(a.age_computed)

        for s in a.schedule:
            if s.coach:
                coach_load[s.coach] = coach_load.get(s.coach, 0) + 1

    snapshot = RosterSnapshot(
        branch_id=roster.branch_id,
        period=period,
        snapshot_data={
            "total_athletes": len(roster.athletes),
            "enrollment_by_level": level_counts,
            "enrollment_by_type": type_counts,
            "segment_mix": segment_counts,
            "gender_split": gender_counts,
            "age_stats": {
                "min": min(ages) if ages else None,
                "max": max(ages) if ages else None,
                "avg": round(sum(ages) / len(ages), 1) if ages else None,
                "count": len(ages),
            },
            "coach_load": coach_load,
        },
    )
    db.add(snapshot)
    await db.commit()
    logger.info(f"Saved roster snapshot for branch {roster.branch_id}, period {period}")
