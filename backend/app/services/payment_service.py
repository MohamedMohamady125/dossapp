"""Payment + Receipt service — records payments, generates receipts, triggers notifications."""

import logging
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.payment import Payment
from app.models.receipt import Receipt
from app.services.receipt_generator import generate_receipt_pdf
from app.services.notifications import enqueue_notification
from app.utils.phone import normalize_phone

logger = logging.getLogger(__name__)


async def get_next_receipt_sequence(db: AsyncSession) -> int:
    """Get the next P- receipt sequence number."""
    # Count existing P- receipts + 1 (safe under single-process; use DB sequence in production)
    result = await db.execute(
        select(func.count()).where(Receipt.receipt_number.like("P-%"))
    )
    count = result.scalar() or 0
    return count + 1


async def record_paymob_payment(
    db: AsyncSession,
    branch_id: int,
    athlete_number: int,
    period: str,
    amount_paid: Decimal,
    amount_owed: Optional[Decimal],
    paymob_transaction_id: str,
    athlete_name: str,
    branch_name: str,
    level: Optional[str] = None,
    athlete_type: Optional[str] = None,
    phone: Optional[str] = None,
    email: Optional[str] = None,
) -> Optional[Receipt]:
    """Record a Paymob payment and generate receipt. Idempotent."""

    # Check idempotency
    existing = await db.execute(
        select(Payment).where(
            Payment.branch_id == branch_id,
            Payment.athlete_number == athlete_number,
            Payment.period == period,
            Payment.source == "paymob",
        )
    )
    if existing.scalar_one_or_none():
        logger.info(f"Paymob payment already recorded for ({branch_id}, {athlete_number}, {period})")
        return None

    # Create payment
    payment = Payment(
        branch_id=branch_id,
        athlete_number=athlete_number,
        period=period,
        source="paymob",
        amount_owed_snapshot=amount_owed,
        amount_paid=amount_paid,
        currency="EGP",
        paymob_transaction_id=paymob_transaction_id,
        status="paid",
        paid_at=datetime.now(timezone.utc),
    )
    db.add(payment)
    await db.flush()

    # Generate receipt
    seq = await get_next_receipt_sequence(db)
    receipt_number = f"P-{seq:06d}"

    normalized_phone = normalize_phone(phone)
    pdf_data = generate_receipt_pdf(
        receipt_number=receipt_number,
        athlete_name=athlete_name,
        athlete_number=athlete_number,
        branch_name=branch_name,
        level=level,
        athlete_type=athlete_type,
        phone=normalized_phone,
        period=period,
        amount_paid=str(amount_paid),
        payment_channel="Online",
        paymob_transaction_id=paymob_transaction_id,
    )

    receipt = Receipt(
        payment_id=payment.id,
        receipt_number=receipt_number,
        pdf_data=pdf_data,
        athlete_name=athlete_name,
        athlete_number=athlete_number,
        branch_name=branch_name,
        level=level,
        athlete_type=athlete_type,
        phone=normalized_phone,
        period=period,
        amount_paid=str(amount_paid),
        payment_channel="Online",
        paymob_transaction_id=paymob_transaction_id,
        send_status={"sms": "pending", "email": "pending", "whatsapp": "pending"},
    )
    db.add(receipt)
    await db.commit()

    # Enqueue notifications
    await _send_receipt_notifications(receipt, pdf_data, normalized_phone, email=email)

    return receipt


async def record_cash_payment(
    db: AsyncSession,
    branch_id: int,
    athlete_number: int,
    period: str,
    amount_paid: Decimal,
    amount_owed: Optional[Decimal],
    excel_receipt_no: str,
    athlete_name: str,
    branch_name: str,
    level: Optional[str] = None,
    athlete_type: Optional[str] = None,
    phone: Optional[str] = None,
    email: Optional[str] = None,
) -> Optional[Receipt]:
    """Record a cash payment detected from Excel and generate receipt. Idempotent."""

    existing = await db.execute(
        select(Payment).where(
            Payment.branch_id == branch_id,
            Payment.athlete_number == athlete_number,
            Payment.period == period,
            Payment.source == "cash",
        )
    )
    if existing.scalar_one_or_none():
        return None

    payment = Payment(
        branch_id=branch_id,
        athlete_number=athlete_number,
        period=period,
        source="cash",
        amount_owed_snapshot=amount_owed,
        amount_paid=amount_paid,
        currency="EGP",
        excel_receipt_no=excel_receipt_no,
        status="paid",
        paid_at=datetime.now(timezone.utc),
    )
    db.add(payment)
    await db.flush()

    receipt_number = f"C-{excel_receipt_no}"

    normalized_phone = normalize_phone(phone)
    pdf_data = generate_receipt_pdf(
        receipt_number=receipt_number,
        athlete_name=athlete_name,
        athlete_number=athlete_number,
        branch_name=branch_name,
        level=level,
        athlete_type=athlete_type,
        phone=normalized_phone,
        period=period,
        amount_paid=str(amount_paid),
        payment_channel="Cash",
    )

    receipt = Receipt(
        payment_id=payment.id,
        receipt_number=receipt_number,
        pdf_data=pdf_data,
        athlete_name=athlete_name,
        athlete_number=athlete_number,
        branch_name=branch_name,
        level=level,
        athlete_type=athlete_type,
        phone=normalized_phone,
        period=period,
        amount_paid=str(amount_paid),
        payment_channel="Cash",
        send_status={"sms": "pending", "email": "pending", "whatsapp": "pending"},
    )
    db.add(receipt)
    await db.commit()

    await _send_receipt_notifications(receipt, pdf_data, normalized_phone, email=email)
    return receipt


async def record_manual_payment(
    db: AsyncSession,
    branch_id: int,
    athlete_number: int,
    period: str,
    amount_paid: Decimal,
    amount_owed: Optional[Decimal],
    athlete_name: str,
    branch_name: str,
    level: Optional[str] = None,
    athlete_type: Optional[str] = None,
    phone: Optional[str] = None,
    email: Optional[str] = None,
) -> Optional[Receipt]:
    """Record a manual (admin-marked) payment and generate receipt. Idempotent."""

    existing = await db.execute(
        select(Payment).where(
            Payment.branch_id == branch_id,
            Payment.athlete_number == athlete_number,
            Payment.period == period,
            Payment.status == "paid",
        )
    )
    if existing.scalar_one_or_none():
        return None

    payment = Payment(
        branch_id=branch_id,
        athlete_number=athlete_number,
        period=period,
        source="cash",
        amount_owed_snapshot=amount_owed,
        amount_paid=amount_paid,
        currency="EGP",
        status="paid",
        paid_at=datetime.now(timezone.utc),
    )
    db.add(payment)
    await db.flush()

    seq = await get_next_receipt_sequence(db)
    receipt_number = f"M-{seq:06d}"

    normalized_phone = normalize_phone(phone)
    pdf_data = generate_receipt_pdf(
        receipt_number=receipt_number,
        athlete_name=athlete_name,
        athlete_number=athlete_number,
        branch_name=branch_name,
        level=level,
        athlete_type=athlete_type,
        phone=normalized_phone,
        period=period,
        amount_paid=str(amount_paid),
        payment_channel="Manual",
    )

    receipt = Receipt(
        payment_id=payment.id,
        receipt_number=receipt_number,
        pdf_data=pdf_data,
        athlete_name=athlete_name,
        athlete_number=athlete_number,
        branch_name=branch_name,
        level=level,
        athlete_type=athlete_type,
        phone=normalized_phone,
        period=period,
        amount_paid=str(amount_paid),
        payment_channel="Manual",
        send_status={"sms": "pending", "email": "pending", "whatsapp": "pending"},
    )
    db.add(receipt)
    await db.commit()

    await _send_receipt_notifications(receipt, pdf_data, normalized_phone, email=email)
    return receipt


async def _send_receipt_notifications(
    receipt: Receipt, pdf_data: bytes, phone: Optional[str], email: Optional[str] = None,
):
    """Enqueue receipt notifications across all available channels."""
    body = (
        f"Aqua Athletic Academy - Payment Receipt\n"
        f"Receipt #{receipt.receipt_number}\n"
        f"Athlete: {receipt.athlete_name}\n"
        f"Period: {receipt.period}\n"
        f"Amount: {receipt.amount_paid} EGP\n"
        f"Status: PAID\n"
        f"Thank you!"
    )

    if phone:
        await enqueue_notification("sms", phone, body, receipt_id=receipt.id)
        await enqueue_notification("whatsapp", phone, body, attachment=pdf_data, receipt_id=receipt.id)

    if email:
        await enqueue_notification(
            "email", email, body,
            subject=f"Aqua Athletic Receipt {receipt.receipt_number} — {receipt.period}",
            attachment=pdf_data, receipt_id=receipt.id,
        )
