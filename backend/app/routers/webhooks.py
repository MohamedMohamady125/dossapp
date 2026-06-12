"""Paymob webhook endpoint — HMAC-verified payment confirmation."""

import logging
import re
from decimal import Decimal

from fastapi import APIRouter, Request, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models.account import Account
from app.services.paymob import verify_hmac
from app.services.payment_service import record_paymob_payment
from app.utils.phone import normalize_phone

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/webhooks", tags=["webhooks"])


@router.post("/paymob")
async def paymob_webhook(request: Request):
    """Handle Paymob transaction callback. Verify HMAC, record payment, generate receipt."""

    body = await request.json()
    received_hmac = request.query_params.get("hmac", "")

    obj = body.get("obj", {})

    if not verify_hmac(obj, received_hmac):
        logger.warning("Paymob webhook HMAC verification failed")
        raise HTTPException(status_code=403, detail="Invalid HMAC")

    success = obj.get("success", False)
    if not success:
        logger.info(f"Paymob webhook: transaction not successful (id={obj.get('id')})")
        return {"status": "ignored", "reason": "not successful"}

    # Extract merchant_order_id → parse branch_id, athlete_number, period
    order = obj.get("order", {})
    merchant_order_id = order.get("merchant_order_id", "")
    # Expected format: AQUA-{branch_id}-{athlete_number}-{period}
    match = re.match(r"AQUA-(\d+)-(\d+)-(.+)", merchant_order_id)
    if not match:
        logger.error(f"Cannot parse merchant_order_id: {merchant_order_id}")
        return {"status": "error", "reason": "invalid order id format"}

    branch_id = int(match.group(1))
    athlete_number = int(match.group(2))
    period = match.group(3)

    amount_cents = obj.get("amount_cents", 0)
    amount_egp = Decimal(amount_cents) / Decimal(100)
    transaction_id = str(obj.get("id", ""))

    # Look up athlete info from roster for receipt generation
    from app.main import roster_source
    roster = await roster_source.get_branch_roster(branch_id)
    athlete_name = "Unknown"
    branch_name = "Unknown"
    level = None
    athlete_type = None
    phone = None
    amount_owed = None

    email = None
    if roster:
        branch_name = roster.branch_name
        athlete = next((a for a in roster.athletes if a.athlete_number == athlete_number), None)
        if athlete:
            athlete_name = athlete.name
            level = athlete.step
            athlete_type = athlete.type
            phone = normalize_phone(athlete.phone1)
            if athlete.pay:
                try:
                    amount_owed = Decimal(athlete.pay)
                except Exception:
                    pass

    # Look up account email if available
    async with async_session() as db:
        acct_result = await db.execute(
            select(Account.email).where(
                Account.branch_id == branch_id,
                Account.athlete_number == athlete_number,
            )
        )
        email = acct_result.scalar_one_or_none()

    async with async_session() as db:
        receipt = await record_paymob_payment(
            db=db,
            branch_id=branch_id,
            athlete_number=athlete_number,
            period=period,
            amount_paid=amount_egp,
            amount_owed=amount_owed,
            paymob_transaction_id=transaction_id,
            athlete_name=athlete_name,
            branch_name=branch_name,
            level=level,
            athlete_type=athlete_type,
            phone=phone,
            email=email,
        )

    if receipt:
        logger.info(f"Paymob payment recorded: {receipt.receipt_number}")
        return {"status": "ok", "receipt": receipt.receipt_number}
    else:
        return {"status": "duplicate"}
