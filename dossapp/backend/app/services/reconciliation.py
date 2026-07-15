"""Excel cash reconciliation pass.

After each Excel refresh, detect new cash payments (Receipt No. present)
and create payment + receipt records idempotently.
"""

import logging
from datetime import datetime
from decimal import Decimal, InvalidOperation

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.services.roster_source import BranchRoster
from app.services.payment_service import record_cash_payment

logger = logging.getLogger(__name__)


def _current_period() -> str:
    """Current billing period as YYYY-MM."""
    now = datetime.now()
    return now.strftime("%Y-%m")


async def reconcile_branch(roster: BranchRoster, db: AsyncSession) -> int:
    """Run reconciliation for a branch. Returns count of new cash payments created."""
    period = _current_period()
    created_count = 0

    # Pre-fetch all account emails for this branch in one query (avoid N+1)
    acct_result = await db.execute(
        select(Account.athlete_number, Account.email).where(
            Account.branch_id == roster.branch_id,
        )
    )
    email_map = {row[0]: row[1] for row in acct_result.all()}

    for athlete in roster.athletes:
        if not athlete.pay:
            continue

        try:
            amount = Decimal(athlete.pay)
        except (InvalidOperation, ValueError):
            logger.warning(
                f"Branch {roster.branch_id}, athlete {athlete.athlete_number}: "
                f"unparseable pay value '{athlete.pay}'"
            )
            continue

        if amount <= 0:
            continue

        receipt_no = athlete.receipt_no or f"{roster.branch_id}-{athlete.athlete_number}"
        email = email_map.get(athlete.athlete_number)

        receipt = await record_cash_payment(
            db=db,
            branch_id=roster.branch_id,
            athlete_number=athlete.athlete_number,
            period=period,
            amount_paid=amount,
            amount_owed=amount,
            excel_receipt_no=receipt_no,
            athlete_name=athlete.name,
            branch_name=roster.branch_name,
            level=athlete.step,
            athlete_type=athlete.type,
            phone=athlete.phone1,
            email=email,
        )
        if receipt:
            created_count += 1
            logger.info(
                f"Cash payment recorded: branch={roster.branch_id}, "
                f"athlete={athlete.athlete_number}, receipt={receipt.receipt_number}"
            )

    return created_count
