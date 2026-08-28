"""Payment + Receipt service — records payments, generates receipts, triggers notifications."""

import logging
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional

from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.payment import Payment
from app.models.receipt import Receipt
from app.services.receipt_generator import generate_receipt_pdf
from app.services.notifications import enqueue_notification
from app.utils.phone import normalize_phone

logger = logging.getLogger(__name__)


import asyncio as _aio

_receipt_lock: Optional[_aio.Lock] = None


def _get_receipt_lock() -> _aio.Lock:
    global _receipt_lock
    if _receipt_lock is None:
        _receipt_lock = _aio.Lock()
    return _receipt_lock


async def get_next_receipt_number(db: AsyncSession, excel_receipts: Optional[list[str]] = None) -> str:
    """Get the next receipt number as a plain integer continuing the Excel sequence.

    Uses an async lock to prevent concurrent calls from generating the same number.
    Combines max from DB receipts and the Excel sheet's existing receipts,
    then returns max + 1. Ensures the number doesn't collide with any existing receipt.
    """
    import re

    async with _get_receipt_lock():
        # Collect all existing receipt number strings
        result = await db.execute(select(Receipt.receipt_number))
        db_numbers = set(rn for rn in result.scalars().all() if rn)
        excel_set = set(str(rn).strip() for rn in (excel_receipts or []) if rn)
        all_existing = db_numbers | excel_set

        # Find max numeric value across all receipts
        max_num = 0
        for rn in all_existing:
            for part in str(rn).split("/"):  # handle "787/973" style
                m = re.search(r"(\d+)", part)
                if m:
                    num = int(m.group(1))
                    if num > max_num:
                        max_num = num

        # Pick next number, skip if it somehow already exists
        candidate = max_num + 1
        while str(candidate) in all_existing:
            candidate += 1
        return str(candidate)


async def record_online_payment(
    db: AsyncSession,
    branch_id: int,
    athlete_number: int,
    period: str,
    amount_paid: Decimal,
    amount_owed: Optional[Decimal],
    transaction_id: str,
    athlete_name: str,
    branch_name: str,
    source: str = "easykash",
    level: Optional[str] = None,
    athlete_type: Optional[str] = None,
    phone: Optional[str] = None,
    email: Optional[str] = None,
) -> Optional[Receipt]:
    """Record an online gateway payment and generate receipt. Idempotent + race-safe."""

    # Check idempotency (fast path)
    existing = await db.execute(
        select(Payment).where(
            Payment.branch_id == branch_id,
            Payment.athlete_number == athlete_number,
            Payment.period == period,
            Payment.source == source,
        )
    )
    if existing.scalar_one_or_none():
        logger.info(f"{source} payment already recorded for ({branch_id}, {athlete_number}, {period})")
        return None

    # Create payment — unique constraint catches concurrent duplicates
    payment = Payment(
        branch_id=branch_id,
        athlete_number=athlete_number,
        period=period,
        source=source,
        amount_owed_snapshot=amount_owed,
        amount_paid=amount_paid,
        currency="EGP",
        paymob_transaction_id=transaction_id,
        status="paid",
        paid_at=datetime.now(timezone.utc),
    )
    db.add(payment)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        logger.info(f"{source} duplicate caught by constraint for ({branch_id}, {athlete_number}, {period})")
        return None

    # Generate receipt
    receipt_number = await get_next_receipt_number(db)

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
        paymob_transaction_id=transaction_id,
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
        paymob_transaction_id=transaction_id,
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
    """Record a cash payment detected from Excel and generate receipt. Idempotent + race-safe."""

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
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        logger.info(f"Cash payment duplicate caught for ({branch_id}, {athlete_number}, {period})")
        return None

    receipt_number = str(excel_receipt_no)

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
    payment_method: str = "cash",
    excel_receipts: Optional[list[str]] = None,
) -> Optional[Receipt]:
    """Record a manual (admin-marked) payment and generate receipt. Idempotent + race-safe."""

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
        source=payment_method,
        amount_owed_snapshot=amount_owed,
        amount_paid=amount_paid,
        currency="EGP",
        status="paid",
        paid_at=datetime.now(timezone.utc),
    )
    db.add(payment)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        logger.info(f"Manual payment duplicate caught for ({branch_id}, {athlete_number}, {period})")
        return None

    receipt_number = await get_next_receipt_number(db, excel_receipts=excel_receipts)

    channel = "Cash" if payment_method == "cash" else "Card"
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
        payment_channel=channel,
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
        payment_channel=channel,
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
        f"Aquathletic Swimming Academy - Payment Receipt\n"
        f"Receipt #{receipt.receipt_number}\n"
        f"Branch: {receipt.branch_name}\n"
        f"Athlete: {receipt.athlete_name}\n"
        f"Period: {receipt.period}\n"
        f"Amount: {receipt.amount_paid} EGP\n"
        f"Status: PAID ✓\n\n"
        f"Thank you for choosing Aquathletic!"
    )

    if phone:
        await enqueue_notification("sms", phone, body, receipt_id=receipt.id)
        await enqueue_notification("whatsapp", phone, body, attachment=pdf_data, receipt_id=receipt.id)

    if email:
        await enqueue_notification(
            "email", email, body,
            subject=f"Aquathletic Receipt {receipt.receipt_number} — {receipt.period}",
            attachment=pdf_data, receipt_id=receipt.id,
        )
