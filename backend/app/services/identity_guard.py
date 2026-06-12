"""Identity guard — run during cache refresh to detect athlete number reuse.

Compares current Excel athlete names against stored account snapshots.
Flags mismatches so old accounts don't see new athletes' data.
"""

import logging
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.services.roster_source import BranchRoster

logger = logging.getLogger(__name__)


async def check_identity_mismatches(roster: BranchRoster, db: AsyncSession) -> int:
    """Check all accounts for this branch against current Excel data.

    Returns count of newly flagged mismatches.
    """
    # Get all active accounts for this branch
    result = await db.execute(
        select(Account).where(
            Account.branch_id == roster.branch_id,
            Account.status == "active",
        )
    )
    accounts = result.scalars().all()
    if not accounts:
        return 0

    # Build athlete lookup from current roster
    athlete_by_num = {a.athlete_number: a for a in roster.athletes}

    flagged = 0
    for account in accounts:
        athlete = athlete_by_num.get(account.athlete_number)
        if not athlete:
            # Absent from roster — not a mismatch, just "no enrollment"
            continue

        # Compare names (case-insensitive, stripped)
        excel_name = (athlete.name or "").strip().lower()
        stored_name = (account.name_at_creation or "").strip().lower()

        if not stored_name or not excel_name:
            continue

        # Clear mismatch check — neither name contains the other
        if stored_name not in excel_name and excel_name not in stored_name:
            logger.warning(
                f"Identity mismatch detected during refresh: account {account.id} "
                f"({account.branch_id}, {account.athlete_number}) — "
                f"stored='{account.name_at_creation}', excel='{athlete.name}'"
            )
            account.status = "identity_mismatch"
            db.add(account)
            flagged += 1

    if flagged:
        await db.commit()
        logger.info(f"Flagged {flagged} identity mismatches for branch {roster.branch_id}")

    return flagged
