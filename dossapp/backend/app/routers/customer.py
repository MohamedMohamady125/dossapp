"""Customer endpoints — profile, bill, pay, receipts."""

from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.payment import Payment
from app.models.receipt import Receipt
from app.routers.deps import get_current_customer
from app.schemas.athlete import AthleteProfile, BillResponse, ScheduleSlot
from app.schemas.payment import PaymentIntentResponse, ReceiptOut
from app.services.notifications import enqueue_notification
from app.utils.phone import normalize_phone

router = APIRouter(prefix="/me", tags=["customer"])


def _get_roster_source():
    from app.main import roster_source
    return roster_source


@router.get("/", response_model=AthleteProfile)
async def get_profile(account: Account = Depends(get_current_customer)):
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
    )


@router.get("/bill", response_model=BillResponse)
async def get_bill(account: Account = Depends(get_current_customer), db: AsyncSession = Depends(get_db)):
    source = _get_roster_source()
    roster = await source.get_branch_roster(account.branch_id)
    period = datetime.now().strftime("%Y-%m")

    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")

    athlete = next((a for a in roster.athletes if a.athlete_number == account.athlete_number), None)
    if not athlete:
        return BillResponse(period=period, no_enrollment=True, branch_name=roster.branch_name)

    # Check if already paid
    result = await db.execute(
        select(Payment).where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
            Payment.period == period,
            Payment.status == "paid",
        )
    )
    payment = result.scalar_one_or_none()

    receipt_number = None
    if payment:
        receipt_result = await db.execute(
            select(Receipt.receipt_number).where(Receipt.payment_id == payment.id)
        )
        receipt_number = receipt_result.scalar_one_or_none()

    return BillResponse(
        period=period,
        amount_owed=athlete.pay,
        is_paid=payment is not None,
        receipt_number=receipt_number,
        branch_name=roster.branch_name,
        schedule=[
            ScheduleSlot(coach=s.coach, time_block=s.time_block, day_pair=s.day_pair)
            for s in athlete.schedule
        ],
    )


@router.post("/pay/paymob/intent", response_model=PaymentIntentResponse)
async def create_pay_intent(account: Account = Depends(get_current_customer), db: AsyncSession = Depends(get_db)):
    source = _get_roster_source()
    roster = await source.get_branch_roster(account.branch_id)
    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")

    athlete = next((a for a in roster.athletes if a.athlete_number == account.athlete_number), None)
    if not athlete:
        raise HTTPException(status_code=404, detail="No active enrollment")

    if not athlete.pay:
        raise HTTPException(status_code=400, detail="No bill amount set for this period")

    # Check not already paid
    period = datetime.now().strftime("%Y-%m")
    result = await db.execute(
        select(Payment).where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
            Payment.period == period,
            Payment.status == "paid",
        )
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Already paid for this period")

    amount = Decimal(athlete.pay)
    phone = normalize_phone(athlete.phone1)

    from app.services.paymob import create_payment_intent
    intent = await create_payment_intent(
        amount_egp=amount,
        athlete_name=athlete.name,
        athlete_number=athlete.athlete_number,
        branch_id=account.branch_id,
        period=period,
        phone=phone,
        email=account.email,
    )

    if not intent:
        raise HTTPException(status_code=502, detail="Payment service unavailable")

    return PaymentIntentResponse(token=intent["token"], amount=str(amount))


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
