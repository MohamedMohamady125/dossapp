"""Auto-provision coach login accounts from coach names found in Excel rosters.

Each unique coach name in a branch gets one AdminUser with role='coach',
a default password, and must_change_password=True.
"""

import logging
import re

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.admin_user import AdminUser
from app.services.roster_source import BranchRoster
from app.utils.auth import hash_password

logger = logging.getLogger(__name__)

DEFAULT_COACH_PASSWORD = "coach123"


def normalize_coach_name(name: str) -> str:
    """Normalize for matching: lowercase, trim, drop a leading 'coach' word.

    'Coach Ahmed', 'coach ahmed ' and 'Ahmed' all normalize to 'ahmed'.
    """
    clean = (name or "").strip().lower()
    clean = re.sub(r"^coach\s+", "", clean)
    return re.sub(r"\s+", " ", clean)


def coach_username(name: str, branch_id: int) -> str:
    """Deterministic username, e.g. 'Coach Ahmed' + branch 1 -> 'ahmed.1'."""
    slug = re.sub(r"[^a-z0-9]+", ".", normalize_coach_name(name)).strip(".")
    return f"{slug}.{branch_id}"


def _roster_coach_names(roster: BranchRoster) -> list[str]:
    """Unique coach names from the Skills sheet plus attendance schedule entries."""
    seen: dict[str, str] = {}
    candidates = list(roster.coaches)
    for athlete in roster.athletes:
        for slot in athlete.schedule:
            if slot.coach:
                candidates.append(slot.coach)

    for name in candidates:
        key = normalize_coach_name(name)
        if key and key not in seen:
            seen[key] = name.strip()
    return list(seen.values())


async def sync_coach_accounts(roster: BranchRoster, db: AsyncSession) -> int:
    """Create login accounts for any coach in the roster that doesn't have one yet."""
    result = await db.execute(
        select(AdminUser).where(
            AdminUser.role == "coach",
            AdminUser.assigned_branch_id == roster.branch_id,
        )
    )
    existing_keys = {normalize_coach_name(c.coach_name or "") for c in result.scalars().all()}

    created = 0
    for name in _roster_coach_names(roster):
        if normalize_coach_name(name) in existing_keys:
            continue  # Already provisioned

        username = coach_username(name, roster.branch_id)
        taken = await db.execute(select(AdminUser).where(AdminUser.username == username))
        if taken.scalars().first():
            logger.warning(f"Coach username '{username}' already taken — skipping '{name}'")
            continue

        db.add(AdminUser(
            username=username,
            password_hash=hash_password(DEFAULT_COACH_PASSWORD),
            role="coach",
            coach_name=name,
            assigned_branch_id=roster.branch_id,
            must_change_password=True,
            is_active=True,
        ))
        created += 1
        logger.info(f"Provisioned coach account '{username}' for '{name}' (branch {roster.branch_id})")

    if created:
        await db.commit()
    return created
