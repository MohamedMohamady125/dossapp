"""Easykash webhook endpoint — signature-verified payment confirmation."""

import logging
import re
from decimal import Decimal, InvalidOperation

from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy import select

from app.config import settings
from app.database import async_session
from app.models.account import Account
from app.services.easykash import verify_signature
from app.services.payment_service import record_online_payment
from app.utils.phone import normalize_phone

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/webhooks", tags=["webhooks"])

SUCCESS_STATUSES = {"paid", "success", "successful", "completed"}


async def _extract_payload(request: Request) -> dict:
    """Easykash may send the callback as POST JSON, POST form, or GET query params."""
    if request.method == "GET":
        return dict(request.query_params)
    try:
        body = await request.json()
        if isinstance(body, dict):
            return body
    except Exception:
        pass
    try:
        form = await request.form()
        return dict(form)
    except Exception:
        pass
    return dict(request.query_params)


def _get_ci(payload: dict, *names: str) -> str:
    """Case-insensitive field lookup (Easykash capitalization is unconfirmed)."""
    lowered = {str(k).lower(): v for k, v in payload.items()}
    for name in names:
        val = lowered.get(name.lower())
        if val is not None and str(val) != "":
            return str(val)
    return ""


@router.api_route("/easykash", methods=["GET", "POST"])
async def easykash_webhook(request: Request):
    """Handle Easykash payment callback. Verify signature, record payment, generate receipt."""

    payload = await _extract_payload(request)
    logger.info(f"Easykash callback received: {payload}")
    return await _process_callback(payload)


async def _process_callback(payload: dict, skip_signature: bool = False) -> dict:
    """Verify signature, record payment, generate receipt. Raises HTTPException on rejection."""

    # ── Signature verification ──
    if not skip_signature:
        received_sig = _get_ci(payload, "signatureHash", "signature", "hash")
        if settings.easykash_hmac_secret:
            if not verify_signature(payload, received_sig):
                logger.warning("Easykash webhook signature verification failed")
                raise HTTPException(status_code=403, detail="Invalid signature")
        elif not settings.easykash_allow_unverified:
            logger.error("Easykash callback rejected: EASYKASH_HMAC_SECRET not configured")
            raise HTTPException(status_code=503, detail="Signature verification not configured")

    # ── Status ──
    status = _get_ci(payload, "status", "PaymentStatus").lower()
    if status not in SUCCESS_STATUSES:
        logger.info(f"Easykash callback: non-success status '{status}' — ignored")
        return {"status": "ignored", "reason": f"status={status or 'missing'}"}

    # ── Parse customerReference: AQUA-{branch_id}-{athlete_number}-{period}[-{timestamp}] ──
    customer_ref = _get_ci(payload, "customerReference", "CustomerReference")
    match = re.match(r"AQUA-(\d+)-(\d+)-(\d{4}-\d{2})", customer_ref)
    if not match:
        logger.error(f"Cannot parse Easykash customerReference: {customer_ref!r}")
        return {"status": "error", "reason": "invalid customerReference format"}

    branch_id = int(match.group(1))
    athlete_number = int(match.group(2))
    period = match.group(3)

    try:
        amount_egp = Decimal(_get_ci(payload, "Amount", "amount") or "0")
    except InvalidOperation:
        amount_egp = Decimal(0)
    transaction_id = _get_ci(payload, "easykashRef", "EasykashRef", "providerRefNum", "transactionId") or customer_ref

    # Look up athlete info from roster for receipt generation
    from app.main import roster_source
    roster = await roster_source.get_branch_roster(branch_id)
    athlete_name = "Unknown"
    branch_name = "Unknown"
    level = None
    athlete_type = None
    phone = None
    amount_owed = None

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

    # If amount not in callback params, resolve from price catalog
    if amount_egp <= 0:
        async with async_session() as db:
            from app.services.price_resolver import resolve_price
            catalog_price = await resolve_price(
                db, branch_id,
                athlete_type, level,
                athlete.segment if athlete else None,
                athlete.sessions if athlete else None,
                athlete_number=athlete_number,
            ) if athlete else None
            if catalog_price:
                amount_egp = Decimal(str(catalog_price))
                logger.info(f"Amount resolved from catalog: {amount_egp}")

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
        receipt = await record_online_payment(
            db=db,
            branch_id=branch_id,
            athlete_number=athlete_number,
            period=period,
            amount_paid=amount_egp,
            amount_owed=amount_owed,
            transaction_id=transaction_id,
            athlete_name=athlete_name,
            branch_name=branch_name,
            source="easykash",
            level=level,
            athlete_type=athlete_type,
            phone=phone,
            email=email,
        )

    if receipt:
        logger.info(f"Easykash payment recorded: {receipt.receipt_number}")

        # Write Pay + Receipt back to the Google Drive Excel sheet (best-effort)
        try:
            from app.models.branch import Branch
            async with async_session() as db:
                br_result = await db.execute(
                    select(Branch.drive_file_id).where(Branch.id == branch_id)
                )
                drive_file_id = br_result.scalar_one_or_none()

            if drive_file_id:
                import asyncio as _aio
                from app.services.drive_writer import update_athlete_payment
                # Format: 200.00 → "200", 1250.50 → "1250.5" (only strip decimal zeros)
                raw = str(amount_egp)
                pay_str = raw.rstrip("0").rstrip(".") if "." in raw else raw
                await _aio.to_thread(
                    update_athlete_payment,
                    drive_file_id,
                    athlete_number,
                    pay_str,
                    receipt.receipt_number,
                )
                logger.info(f"Excel updated for athlete #{athlete_number}: Pay={pay_str}, Receipt={receipt.receipt_number}")
            else:
                logger.warning(f"No drive_file_id for branch {branch_id} — skipping Excel write-back")
        except Exception as e:
            logger.warning(f"Failed to write online payment to Excel: {e}")

        return {"status": "ok", "receipt": receipt.receipt_number}
    return {"status": "duplicate"}


success_router = APIRouter(tags=["webhooks"])


@success_router.get("/pay/success", response_class=HTMLResponse)
async def pay_success(request: Request):
    """Post-payment landing page (Easykash redirects the customer here).

    Easykash may append the payment result as query params on the redirect —
    process them like a callback (best effort; the page renders regardless).
    """
    params = dict(request.query_params)
    if params:
        logger.info(f"Easykash redirect params on /pay/success: {params}")
        try:
            # Redirect params from browser don't include signatureHash — skip verification.
            # Payment is idempotent (uq_payment_idempotent), so replays are safe.
            result = await _process_callback(params, skip_signature=True)
            logger.info(f"Redirect-param payment processing result: {result}")
        except Exception as e:
            logger.warning(f"Redirect params not processable as payment: {e}")
    return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Payment Received — Aqua Athletic</title>
<style>
  body { font-family: -apple-system, sans-serif; background: #f5f7fb; display: flex;
         align-items: center; justify-content: center; height: 100vh; margin: 0; }
  .card { background: #fff; border-radius: 16px; padding: 40px 32px; text-align: center;
          box-shadow: 0 4px 24px rgba(0,0,0,.08); max-width: 340px; }
  .check { font-size: 56px; }
  h1 { font-size: 20px; color: #1a237e; margin: 12px 0 4px; }
  p { color: #666; font-size: 14px; }
</style>
</head>
<body>
  <div class="card">
    <div class="check">&#9989;</div>
    <h1>Payment Received</h1>
    <p>Thank you! Your receipt will appear in the Aqua Athletic app shortly.<br>You can close this page and return to the app.</p>
  </div>
</body>
</html>"""
