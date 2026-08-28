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
from app.models.bill_override import BillOverride
from app.services.roster_source import BranchRoster
from app.services.payment_service import record_cash_payment
from app.services.price_resolver import resolve_price

logger = logging.getLogger(__name__)


def _current_period() -> str:
    """Current billing period as YYYY-MM."""
    from app.utils.billing import current_billing_period
    return current_billing_period()


async def reconcile_branch(roster: BranchRoster, db: AsyncSession) -> int:
    """Run reconciliation for a branch. Returns count of new cash payments created."""
    period = roster.period or _current_period()
    created_count = 0

    # Pre-fetch all account emails + bill overrides for this branch (avoid N+1)
    acct_result = await db.execute(
        select(Account.athlete_number, Account.email).where(
            Account.branch_id == roster.branch_id,
        )
    )
    email_map = {row[0]: row[1] for row in acct_result.all()}

    override_result = await db.execute(
        select(BillOverride).where(BillOverride.branch_id == roster.branch_id)
    )
    override_map = {o.athlete_number: o.amount for o in override_result.scalars().all()}

    for athlete in roster.athletes:
        # Consider paid if pay column has a positive amount OR receipt column has a value
        has_pay = bool(athlete.pay)
        has_receipt = bool(athlete.receipt_no and str(athlete.receipt_no).strip() not in ("", "0", "None"))

        if not has_pay and not has_receipt:
            continue

        amount = Decimal(0)
        if has_pay:
            try:
                amount = Decimal(athlete.pay)
            except (InvalidOperation, ValueError):
                logger.warning(
                    f"Branch {roster.branch_id}, athlete {athlete.athlete_number}: "
                    f"unparseable pay value '{athlete.pay}'"
                )
                if not has_receipt:
                    continue

        # If receipt exists but no valid pay amount, resolve price:
        # 1st priority: admin-set custom bill (BillOverride)
        # 2nd priority: price catalog
        if amount <= 0 and has_receipt:
            override = override_map.get(athlete.athlete_number)
            if override:
                amount = Decimal(str(override))
            else:
                catalog_price = await resolve_price(
                    db, roster.branch_id, athlete.type, athlete.step, athlete.segment, athlete.sessions,
                    athlete_number=athlete.athlete_number,
                )
                amount = catalog_price if catalog_price is not None else Decimal(0)
            if amount <= 0:
                continue

        receipt_no = athlete.receipt_no or f"{roster.branch_id}-{athlete.athlete_number}"
        email = email_map.get(athlete.athlete_number)

        # amount_owed: check override first, then catalog
        override = override_map.get(athlete.athlete_number)
        if override:
            amount_owed = Decimal(str(override))
        else:
            catalog_price = await resolve_price(
                db, roster.branch_id, athlete.type, athlete.step, athlete.segment, athlete.sessions,
                athlete_number=athlete.athlete_number,
            )
            amount_owed = catalog_price if catalog_price is not None else amount

        receipt = await record_cash_payment(
            db=db,
            branch_id=roster.branch_id,
            athlete_number=athlete.athlete_number,
            period=period,
            amount_paid=amount,
            amount_owed=amount_owed,
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
