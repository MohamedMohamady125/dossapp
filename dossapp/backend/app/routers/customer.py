"""Customer endpoints — profile, bill, pay, receipts."""

from datetime import datetime
from decimal import Decimal
from typing import Optional

from app.utils.billing import current_billing_period

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.payment import Payment
from app.models.receipt import Receipt
from pydantic import BaseModel as PydanticBaseModel
from app.routers.deps import get_current_customer, get_current_customer_allow_suspended
from app.schemas.athlete import AthleteProfile, BillResponse, ScheduleSlot
from app.schemas.payment import PaymentIntentResponse, ReceiptOut
from app.services.notifications import enqueue_notification
from app.utils.phone import normalize_phone

router = APIRouter(prefix="/me", tags=["customer"])


class UpdateEmailBody(PydanticBaseModel):
    email: str


class ChangePasswordBody(PydanticBaseModel):
    old_password: str
    new_password: str


def _get_roster_source():
    from app.main import roster_source
    return roster_source


def _fmt_amount(amount) -> str:
    """Decimal → plain string without trailing zeros (800.00 → '800')."""
    s = format(amount, "f")
    return s.rstrip("0").rstrip(".") if "." in s else s



@router.get("/", response_model=AthleteProfile)
async def get_profile(account: Account = Depends(get_current_customer_allow_suspended)):
    source = _get_roster_source()
    roster = await source.get_branch_roster(account.branch_id)
    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")

    athlete = next((a for a in roster.athletes if a.athlete_number == account.athlete_number), None)
    if not athlete:
        return AthleteProfile(
            branch=roster.branch_name,
            branch_id=account.branch_id,
            athlete_number=account.athlete_number,
            name=account.name_at_creation,
            account_status=account.status,
        )

    return AthleteProfile(
        branch=roster.branch_name,
        branch_id=account.branch_id,
        athlete_number=athlete.athlete_number,
        name=athlete.name,
        age=athlete.age_computed,
        date_of_birth=athlete.date_of_birth,
        gender=athlete.gender,
        level=athlete.step,
        type=athlete.type,
        days=athlete.days,
        sessions=athlete.sessions,
        segment=athlete.segment,
        schedule=[
            ScheduleSlot(coach=s.coach, time_block=s.time_block, day_pair=s.day_pair)
            for s in athlete.schedule
        ],
        attendance=athlete.attendance,
        account_status=account.status,
    )


def _is_in_payment_window() -> bool:
    """Payment window: 25th of previous month through 1st of current month (inclusive)."""
    today = datetime.now()
    return today.day >= 25 or today.day <= 1


@router.get("/bill", response_model=BillResponse)
async def get_bill(account: Account = Depends(get_current_customer_allow_suspended), db: AsyncSession = Depends(get_db)):
    source = _get_roster_source()
    roster = await source.get_branch_roster(account.branch_id)

    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")

    # Period comes from the Excel sheet (season column / sheet name), not the calendar
    period = roster.period or current_billing_period()

    athlete = next((a for a in roster.athletes if a.athlete_number == account.athlete_number), None)
    if not athlete:
        return BillResponse(period=period, no_enrollment=True, branch_name=roster.branch_name)

    # Check if already paid (DB payment OR Excel pay column)
    result = await db.execute(
        select(Payment).where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
            Payment.period == period,
            Payment.status == "paid",
        )
    )
    payment = result.scalars().first()

    receipt_number = None
    if payment:
        receipt_result = await db.execute(
            select(Receipt.receipt_number).where(Receipt.payment_id == payment.id)
        )
        receipt_number = receipt_result.scalar_one_or_none()

    # Also check Excel pay column — athlete is paid if EITHER DB or Excel says so
    excel_paid = bool(athlete.pay and athlete.receipt_no)
    is_paid = payment is not None or excel_paid

    # Auto-suspend if payment window closed and athlete hasn't paid
    # But skip if admin approved a reinstatement this month (don't re-suspend)
    if not is_paid and not _is_in_payment_window() and account.status == "active":
        from app.models.reinstatement_request import ReinstatementRequest
        month_start = datetime.now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        reinstatement = await db.execute(
            select(ReinstatementRequest).where(
                ReinstatementRequest.account_id == account.id,
                ReinstatementRequest.status == "approved",
                ReinstatementRequest.reviewed_at >= month_start,
            )
        )
        if not reinstatement.scalar_one_or_none():
            account.status = "suspended"
            db.add(account)
            await db.flush()

    # Previous month payment status
    now = datetime.now()
    if now.month == 1:
        prev_period = f"{now.year - 1}-12"
    else:
        prev_period = f"{now.year}-{now.month - 1:02d}"
    prev_result = await db.execute(
        select(Payment).where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
            Payment.period == prev_period,
            Payment.status == "paid",
        )
    )
    prev_paid = prev_result.scalars().first() is not None

    # Primary: price catalog lookup based on athlete's type/step/segment
    from app.services.price_resolver import resolve_price
    catalog_price = await resolve_price(
        db, account.branch_id, athlete.type, athlete.step, athlete.segment, athlete.sessions
    )

    amount_owed = _fmt_amount(catalog_price) if catalog_price is not None else None

    return BillResponse(
        period=period,
        amount_owed=amount_owed,
        is_paid=is_paid,
        receipt_number=receipt_number or (athlete.receipt_no if excel_paid else None),
        is_suspended=account.status == "suspended",
        branch_name=roster.branch_name,
        schedule=[
            ScheduleSlot(coach=s.coach, time_block=s.time_block, day_pair=s.day_pair)
            for s in athlete.schedule
        ],
        prev_period=prev_period,
        prev_paid=prev_paid,
    )


@router.post("/pay/easykash/checkout", response_model=PaymentIntentResponse)
async def create_pay_checkout(account: Account = Depends(get_current_customer), db: AsyncSession = Depends(get_db)):
    from app.config import settings
    if not settings.easykash_api_key:
        raise HTTPException(status_code=503, detail="Online payment not configured")

    source = _get_roster_source()
    roster = await source.get_branch_roster(account.branch_id)
    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")

    athlete = next((a for a in roster.athletes if a.athlete_number == account.athlete_number), None)
    if not athlete:
        raise HTTPException(status_code=404, detail="No active enrollment")

    # Check not already paid
    period = roster.period or current_billing_period()
    result = await db.execute(
        select(Payment).where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
            Payment.period == period,
            Payment.status == "paid",
        )
    )
    if result.scalars().first():
        raise HTTPException(status_code=400, detail="Already paid for this period")

    # Primary: price catalog lookup
    from app.services.price_resolver import resolve_price
    catalog_price = await resolve_price(
        db, account.branch_id, athlete.type, athlete.step, athlete.segment, athlete.sessions
    )
    if catalog_price is None:
        raise HTTPException(status_code=400, detail="No price set in the pricing list for your program")
    amount = Decimal(_fmt_amount(catalog_price))
    phone = normalize_phone(athlete.phone1)

    from app.services.easykash import create_checkout
    checkout = await create_checkout(
        amount_egp=amount,
        athlete_name=athlete.name,
        athlete_number=athlete.athlete_number,
        branch_id=account.branch_id,
        period=period,
        phone=phone,
        email=account.email,
    )

    if not checkout:
        raise HTTPException(status_code=502, detail="Payment service unavailable")

    return PaymentIntentResponse(url=checkout["url"], amount=str(amount))


@router.get("/receipts", response_model=list[ReceiptOut])
async def list_receipts(account: Account = Depends(get_current_customer), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Receipt)
        .join(Payment, Receipt.payment_id == Payment.id)
        .where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
        )
        .order_by(Receipt.issued_at.desc())
    )
    receipts = result.scalars().all()

    return [
        ReceiptOut(
            id=r.id,
            receipt_number=r.receipt_number,
            period=r.period,
            amount_paid=r.amount_paid,
            payment_channel=r.payment_channel,
            issued_at=r.issued_at,
            athlete_name=r.athlete_name,
            branch_name=r.branch_name,
            level=r.level,
            pdf_available=r.pdf_data is not None,
        )
        for r in receipts
    ]


@router.get("/receipts/{receipt_id}/pdf")
async def download_receipt_pdf(receipt_id: int, account: Account = Depends(get_current_customer), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Receipt)
        .join(Payment, Receipt.payment_id == Payment.id)
        .where(
            Receipt.id == receipt_id,
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
        )
    )
    receipt = result.scalar_one_or_none()
    if not receipt or not receipt.pdf_data:
        raise HTTPException(status_code=404, detail="Receipt not found")

    return Response(
        content=receipt.pdf_data,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="receipt_{receipt.receipt_number}.pdf"'},
    )


@router.post("/receipts/{receipt_id}/resend")
async def resend_receipt(receipt_id: int, account: Account = Depends(get_current_customer), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Receipt)
        .join(Payment, Receipt.payment_id == Payment.id)
        .where(
            Receipt.id == receipt_id,
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
        )
    )
    receipt = result.scalar_one_or_none()
    if not receipt:
        raise HTTPException(status_code=404, detail="Receipt not found")

    if receipt.phone:
        await enqueue_notification("sms", receipt.phone, f"Receipt {receipt.receipt_number}: {receipt.amount_paid} EGP PAID", receipt_id=receipt.id)
        await enqueue_notification("whatsapp", receipt.phone, f"Receipt {receipt.receipt_number}: {receipt.amount_paid} EGP PAID", attachment=receipt.pdf_data, receipt_id=receipt.id)

    return {"message": "Receipt resend queued"}


# ── Profile Updates ──


@router.put("/email")
async def update_email(
    body: UpdateEmailBody,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    import re
    email = body.email.strip().lower()
    if not re.match(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", email):
        raise HTTPException(status_code=400, detail="Invalid email address")

    account.email = email
    db.add(account)
    return {"message": "Email updated successfully"}


@router.put("/password")
async def update_password(
    body: ChangePasswordBody,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    from app.utils.auth import verify_password, hash_password

    if not verify_password(body.old_password, account.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    if len(body.new_password) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters")

    account.password_hash = hash_password(body.new_password)
    db.add(account)
    return {"message": "Password changed successfully"}


# ── Reinstatement ──

class ReinstatementRequestBody(PydanticBaseModel):
    message: Optional[str] = None


@router.get("/reinstatement")
async def get_reinstatement_status(
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    from app.models.reinstatement_request import ReinstatementRequest
    result = await db.execute(
        select(ReinstatementRequest)
        .where(ReinstatementRequest.account_id == account.id)
        .order_by(ReinstatementRequest.created_at.desc())
        .limit(1)
    )
    req = result.scalar_one_or_none()
    if not req:
        return {"status": "none"}
    return {
        "status": req.status,
        "created_at": req.created_at.isoformat() if req.created_at else None,
        "admin_note": req.admin_note,
    }


@router.post("/reinstatement")
async def request_reinstatement(
    body: ReinstatementRequestBody,
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    if account.status != "suspended":
        raise HTTPException(status_code=400, detail="Account is not suspended")

    from app.models.reinstatement_request import ReinstatementRequest
    # Check no pending request exists
    existing = await db.execute(
        select(ReinstatementRequest).where(
            ReinstatementRequest.account_id == account.id,
            ReinstatementRequest.status == "pending",
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="A reinstatement request is already pending")

    req = ReinstatementRequest(
        account_id=account.id,
        branch_id=account.branch_id,
        athlete_number=account.athlete_number,
        message=body.message,
    )
    db.add(req)
    await db.commit()
    return {"message": "Reinstatement request submitted"}
