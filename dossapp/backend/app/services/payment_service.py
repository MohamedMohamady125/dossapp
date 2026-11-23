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


class PaymentNotRecorded(Exception):
    """The payment could not be saved. Callers decide whether to retry."""


import asyncio as _aio

from sqlalchemy import text as _text

_PAYMENT_LOCK_KEY = 7350001


async def _lock_payments(db: AsyncSession) -> None:
    """Let one payment be recorded at a time, across every worker process.

    Receipt numbers are "highest so far + 1". Two workers recording payments
    at the same moment used to pick the same number; the second one then hit
    the unique constraint and its payment was thrown away even though the
    parent had been charged. A Postgres advisory lock, held until this
    transaction commits or rolls back, makes them take turns.
    """
    bind = db.get_bind()
    if bind.dialect.name == "postgresql":
        await db.execute(_text("SELECT pg_advisory_xact_lock(:k)"), {"k": _PAYMENT_LOCK_KEY})


async def _already_paid(db: AsyncSession, branch_id: int, athlete_number: int, period: str, source: Optional[str] = None) -> bool:
    q = select(Payment.id).where(
        Payment.branch_id == branch_id,
        Payment.athlete_number == athlete_number,
        Payment.period == period,
    )
    q = q.where(Payment.source == source) if source else q.where(Payment.status == "paid")
    return (await db.execute(q.limit(1))).first() is not None


async def _render_receipt(**kwargs) -> bytes:
    """PDF rendering takes around a second of CPU. Keep it off the event loop."""
    return await _aio.to_thread(generate_receipt_pdf, **kwargs)


async def get_next_receipt_number(db: AsyncSession, excel_receipts: Optional[list[str]] = None) -> str:
    """Get the next receipt number as a plain integer continuing the Excel sequence.

    Callers must hold _lock_payments() so two workers cannot pick the same number.
    Combines max from DB receipts and the Excel sheet's existing receipts,
    then returns max + 1. Ensures the number doesn't collide with any existing receipt.
    """
    import re

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

    # Check idempotency (fast path), then again once we hold the lock
    if await _already_paid(db, branch_id, athlete_number, period, source=source):
        logger.info(f"{source} payment already recorded for ({branch_id}, {athlete_number}, {period})")
        return None
    await _lock_payments(db)
    if await _already_paid(db, branch_id, athlete_number, period, source=source):
        await db.rollback()
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
    pdf_data = await _render_receipt(
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
    try:
        await db.commit()
    except IntegrityError as e:
        await db.rollback()
        logger.error(f"Receipt {receipt_number} for ({branch_id}, {athlete_number}, {period}) could not be saved: {e.orig}")
        raise PaymentNotRecorded(f"receipt {receipt_number} clashed") from e

    # Enqueue notifications
    await _send_receipt_notifications(receipt, pdf_data, normalized_phone, email=email)
    await _push_payment_received(db, branch_id, receipt, online=True)

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

    # Any paid row counts, not only cash: an online payment is written back
    # into the sheet's Pay column, and must not be recorded again as cash.
    if await _already_paid(db, branch_id, athlete_number, period):
        return None
    await _lock_payments(db)
    if await _already_paid(db, branch_id, athlete_number, period):
        await db.rollback()
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
    # The sheet's receipt number may already be taken (typed twice, or equal
    # to a number the app issued). Keep it readable but make it unique, so
    # one clash does not stop the rest of the sheet from being recorded.
    taken = await db.execute(select(Receipt.id).where(Receipt.receipt_number == receipt_number).limit(1))
    if taken.first() is not None:
        receipt_number = f"{receipt_number}/{branch_id}-{athlete_number}"

    normalized_phone = normalize_phone(phone)
    pdf_data = await _render_receipt(
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
    try:
        await db.commit()
    except IntegrityError as e:
        await db.rollback()
        logger.error(f"Receipt {receipt_number} for ({branch_id}, {athlete_number}, {period}) could not be saved: {e.orig}")
        raise PaymentNotRecorded(f"receipt {receipt_number} clashed") from e

    await _send_receipt_notifications(receipt, pdf_data, normalized_phone, email=email)
    await _push_payment_received(db, branch_id, receipt, online=False)
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

    if await _already_paid(db, branch_id, athlete_number, period):
        return None
    await _lock_payments(db)
    if await _already_paid(db, branch_id, athlete_number, period):
        await db.rollback()
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
    pdf_data = await _render_receipt(
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
    try:
        await db.commit()
    except IntegrityError as e:
        await db.rollback()
        logger.error(f"Receipt {receipt_number} for ({branch_id}, {athlete_number}, {period}) could not be saved: {e.orig}")
        raise PaymentNotRecorded(f"receipt {receipt_number} clashed") from e

    await _send_receipt_notifications(receipt, pdf_data, normalized_phone, email=email)
    await _push_payment_received(db, branch_id, receipt, online=False)
    return receipt


_MONTHS_EN = ["January", "February", "March", "April", "May", "June",
              "July", "August", "September", "October", "November", "December"]
_MONTHS_AR = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
              "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]


def _month_names(period: str) -> tuple[str, str]:
    """'2026-11' -> ('November', 'نوفمبر'). Falls back to the raw period."""
    try:
        m = int(period.split("-")[1])
        return _MONTHS_EN[m - 1], _MONTHS_AR[m - 1]
    except (IndexError, ValueError):
        return period, period


def _money(amount: str) -> str:
    try:
        return f"{float(amount):,.0f}"
    except (TypeError, ValueError):
        return str(amount)


async def _push_payment_received(db: AsyncSession, branch_id: int, receipt: Receipt, online: bool) -> None:
    """Tell the parent their payment went through; tell staff about online ones.

    Runs after the payment is committed and never raises: a push problem must
    not undo or fail a recorded payment. Staff are only told about online
    payments, since cash and card are entered by staff themselves.
    """
    from app.models.account import Account
    from app.services.push_service import send_push_to_account, send_push_to_staff

    month_en, month_ar = _month_names(receipt.period)
    amount = _money(receipt.amount_paid)
    key = f"{branch_id}:{receipt.athlete_number}:{receipt.period}"

    try:
        result = await db.execute(
            select(Account).where(
                Account.branch_id == branch_id,
                Account.athlete_number == receipt.athlete_number,
            )
        )
        account = result.scalars().first()
        if account:
            if account.language == "ar":
                title = "الدفع وصل"
                body = (f"اتدفع {amount} جنيه اشتراك {receipt.athlete_name} عن شهر {month_ar}. "
                        f"الإيصال رقم {receipt.receipt_number} موجود في التطبيق.")
            else:
                title = "Payment received"
                body = (f"{amount} EGP paid for {receipt.athlete_name}'s {month_en} fee. "
                        f"Receipt {receipt.receipt_number} is in the app.")
            await send_push_to_account(
                db, account.id, "payment_received", title, body,
                data={"screen": "receipts", "receipt_number": receipt.receipt_number},
                dedupe_key=f"paid:{key}",
            )
    except Exception as e:
        logger.error(f"Payment push to parent failed ({key}): {e}")
        try:
            await db.rollback()
        except Exception:
            pass

    if online:
        who = f"{receipt.athlete_name} (#{receipt.athlete_number})"
        await send_push_to_staff(
            db, branch_id,
            en=("Online payment received",
                f"{who} paid {amount} EGP online for {month_en}. {receipt.branch_name}."),
            ar=("تم استلام دفع أونلاين",
                f"{who} دفع {amount} جنيه أونلاين عن شهر {month_ar}. {receipt.branch_name}."),
            data={"screen": "payments", "branch_id": branch_id},
            dedupe_key=f"staffpaid:{key}",
        )


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
