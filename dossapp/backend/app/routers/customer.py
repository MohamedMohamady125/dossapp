"""Customer endpoints — profile, bill, pay, receipts."""

import logging
from datetime import datetime
from decimal import Decimal
from typing import Optional

from app.utils.billing import current_billing_period

from fastapi import APIRouter, Depends, HTTPException, Request

logger = logging.getLogger(__name__)
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import undefer

from app.database import get_db
from app.models.account import Account
from app.models.payment import Payment
from app.models.receipt import Receipt
from pydantic import BaseModel as PydanticBaseModel
from app.routers.deps import USABLE_STATUSES, get_current_customer, get_current_customer_allow_suspended, get_linked_accounts
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


def _safe_name(value) -> str:
    """Receipt numbers come from the sheet and may hold slashes or Arabic."""
    import re
    return re.sub(r"[^A-Za-z0-9_-]", "_", str(value)) or "receipt"


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
    """Payment window: 25th of previous month through 1st of current month (inclusive), Egypt time."""
    from app.services.push_triggers import local_now
    today = local_now()
    return today.day >= 25 or today.day <= 1


@router.get("/bill", response_model=BillResponse)
async def get_bill(account: Account = Depends(get_current_customer_allow_suspended), db: AsyncSession = Depends(get_db)):
    logger.info(f"GET /bill for account_id={account.id} athlete_number={account.athlete_number} branch_id={account.branch_id} status={account.status}")
    source = _get_roster_source()
    roster = await source.get_branch_roster(account.branch_id)

    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")

    # Period comes from the Excel sheet (season column / sheet name), not the calendar
    period = roster.period or current_billing_period()

    athlete = next((a for a in roster.athletes if a.athlete_number == account.athlete_number), None)
    if not athlete:
        return BillResponse(period=period, no_enrollment=True, branch_name=roster.branch_name)

    # Source of truth: Excel Pay + Receipt columns (cash/card payments recorded by admin)
    excel_paid = False
    try:
        excel_amount = float(athlete.pay) if athlete.pay else 0
        excel_paid = excel_amount > 0
    except (ValueError, TypeError):
        pass
    # Also treat as paid if receipt number exists in Excel (admin may fill receipt before pay)
    if not excel_paid and athlete.receipt_no:
        receipt_str = str(athlete.receipt_no).strip()
        if receipt_str and receipt_str.lower() not in ("", "none", "0"):
            excel_paid = True

    # Also check DB for any payments (online via EasyKash, or admin-marked cash/card)
    receipt_number = None
    db_paid = False
    result = await db.execute(
        select(Payment).where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
            Payment.period == period,
            Payment.status == "paid",
        )
    )
    payment = result.scalars().first()
    if payment:
        db_paid = True
        receipt_result = await db.execute(
            select(Receipt.receipt_number).where(Receipt.payment_id == payment.id)
        )
        receipt_number = receipt_result.scalar_one_or_none()

    is_paid = excel_paid or db_paid

    # Price first: a swimmer with no price cannot pay, so must not be suspended
    from app.services.price_resolver import resolve_price
    from app.services.push_triggers import local_now, _is_enrolled
    catalog_price = await resolve_price(
        db, account.branch_id, athlete.type, athlete.step, athlete.segment, athlete.sessions,
        athlete_number=account.athlete_number,
    )
    now = local_now()

    # Auto-suspend if the payment window closed and the swimmer has not paid.
    # Same guards as the daily job: only swimmers enrolled this month, only
    # when there is an amount to pay, and only when the sheet is on the
    # current month (a sheet still on last month, or already on next month,
    # says nothing about who owes what today).
    # Skip if admin approved a reinstatement this month (don't re-suspend).
    if (
        not is_paid
        and account.status == "active"
        and not _is_in_payment_window()
        and _is_enrolled(athlete)
        and catalog_price is not None
        and period == now.strftime("%Y-%m")
    ):
        from app.models.reinstatement_request import ReinstatementRequest
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        reinstatement = await db.execute(
            select(ReinstatementRequest).where(
                ReinstatementRequest.account_id == account.id,
                ReinstatementRequest.status == "approved",
                ReinstatementRequest.reviewed_at >= month_start,
            ).limit(1)
        )
        if not reinstatement.scalars().first():
            account.status = "suspended"
            db.add(account)
            await db.commit()

    # Previous month payment status
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
        db, account.branch_id, athlete.type, athlete.step, athlete.segment, athlete.sessions,
        athlete_number=account.athlete_number,
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
async def list_receipts(account: Account = Depends(get_current_customer_allow_suspended), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Receipt, Receipt.pdf_data.isnot(None))
        .join(Payment, Receipt.payment_id == Payment.id)
        .where(
            Payment.branch_id == account.branch_id,
            Payment.athlete_number == account.athlete_number,
        )
        .order_by(Receipt.issued_at.desc())
    )
    rows = result.all()

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
            pdf_available=bool(has_pdf),
        )
        for r, has_pdf in rows
    ]


@router.get("/receipts/{receipt_id}/pdf")
async def download_receipt_pdf(receipt_id: int, account: Account = Depends(get_current_customer_allow_suspended), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Receipt)
        .options(undefer(Receipt.pdf_data))
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
        headers={"Content-Disposition": f'attachment; filename="receipt_{_safe_name(receipt.receipt_number)}.pdf"'},
    )


@router.post("/receipts/{receipt_id}/resend")
async def resend_receipt(receipt_id: int, account: Account = Depends(get_current_customer_allow_suspended), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Receipt)
        .options(undefer(Receipt.pdf_data))
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
    """Change the email. The address must first be proven with a code
    (POST /auth/customer/send-verification, then /auth/customer/verify-code).

    Email is what links a parent's swimmers together, so saving an unproven
    address would hand over another family's children.
    """
    import re
    from datetime import timedelta, timezone
    from app.models.email_verification import EmailVerification

    email = body.email.strip().lower()
    if not re.match(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", email):
        raise HTTPException(status_code=400, detail="Invalid email address")
    if email == (account.email or "").strip().lower():
        return {"message": "Email updated successfully"}

    result = await db.execute(
        select(EmailVerification).where(
            EmailVerification.account_id == account.id,
            func.lower(EmailVerification.email) == email,
            EmailVerification.purpose == "onboarding",
            EmailVerification.verified == True,  # noqa: E712
            EmailVerification.expires_at > datetime.now(timezone.utc) - timedelta(minutes=20),
        ).limit(1)
    )
    if not result.scalars().first():
        raise HTTPException(status_code=400, detail="Verify this email with the code we send before saving it")

    account.email = email
    db.add(account)
    return {"message": "Email updated successfully"}


@router.put("/password")
async def update_password(
    body: ChangePasswordBody,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    import time
    from app.utils.auth import verify_password, hash_password

    # Rate limit: max 5 password attempts per 5 minutes per account
    now = time.time()
    attempts = _delete_attempts.get(account.id, [])
    attempts = [t for t in attempts if now - t < 300]
    if len(attempts) >= 5:
        raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")
    attempts.append(now)
    _delete_attempts[account.id] = attempts

    if not verify_password(body.old_password, account.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    if len(body.new_password) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters")

    # One password for the family: every swimmer on the same verified email
    # changes together, so signing in by email keeps working for all of them.
    for linked in await get_linked_accounts(db, account):
        linked.password_hash = hash_password(body.new_password)
        db.add(linked)
    return {"message": "Password changed successfully"}


# ── Family: several swimmers under one parent ──

class SwitchProfileBody(PydanticBaseModel):
    account_id: int


@router.get("/profiles")
async def list_profiles(
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    """Every swimmer this parent can open, with the current one flagged."""
    from app.routers.auth import build_profiles
    return await build_profiles(db, account)


@router.post("/switch-profile")
async def switch_profile(
    body: SwitchProfileBody,
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    """Open another swimmer of the same parent without signing in again."""
    from datetime import timezone
    from app.routers.auth import build_profiles, customer_token_data
    from app.schemas.auth import TokenResponse
    from app.utils.auth import create_access_token, create_refresh_token

    linked = await get_linked_accounts(db, account)
    target = next((a for a in linked if a.id == body.account_id), None)
    if target is None:
        # Not on this parent's email (or disabled): never reveal which
        raise HTTPException(status_code=404, detail="Swimmer not found on this account")

    target.last_login_at = datetime.now(timezone.utc)
    db.add(target)
    token_data = customer_token_data(target)
    return TokenResponse(
        access_token=create_access_token(token_data),
        refresh_token=create_refresh_token(token_data),
        must_change_password=target.must_change_password,
        profiles=await build_profiles(db, target),
    )



class LinkSwimmerBody(PydanticBaseModel):
    login_code: str
    password: str


@router.post("/link-swimmer")
async def link_swimmer(
    body: LinkSwimmerBody,
    request: Request,
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    """Add another child to a parent who is already signed in.

    The parent has proved their email, and the new child's login code and
    temporary password prove the front desk gave them that child. So the new
    account joins the same email and password with no second verification.
    """
    from app.routers.auth import _check_login_allowed, _record_login_failure, build_profiles
    from app.utils.auth import verify_password_async

    email = (account.email or "").strip().lower()
    if account.must_change_password or not email:
        raise HTTPException(status_code=400, detail="Finish setting up your own account first")

    limiter_id = f"link:{account.id}"
    _check_login_allowed("customer", limiter_id, request)
    wrong = HTTPException(status_code=400, detail="That login code or password is not correct")

    code = body.login_code.strip()
    result = await db.execute(select(Account).where(func.upper(Account.login_code) == code.upper()))
    target = result.scalars().first()
    if not target or not await verify_password_async(body.password, target.password_hash):
        _record_login_failure("customer", limiter_id, request)
        raise wrong
    if target.status not in USABLE_STATUSES:
        raise wrong
    if target.id == account.id or (target.email or "").strip().lower() == email:
        raise HTTPException(status_code=400, detail="This swimmer is already on your account")
    if not target.must_change_password:
        # Someone already finished signing this swimmer up under another email
        raise HTTPException(
            status_code=400,
            detail="This swimmer is already set up. Ask the front desk for new login details.",
        )

    target.email = email
    target.password_hash = account.password_hash
    target.must_change_password = False
    target.temp_password = None
    target.language = account.language
    db.add(target)
    await db.flush()
    return await build_profiles(db, account)


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

    # Tell the branch staff right away; before this they only saw a badge
    # the next time they opened the app.
    from app.services.push_service import send_push_to_staff
    who = f"{account.name_at_creation} (#{account.athlete_number})"
    await send_push_to_staff(
        db, account.branch_id,
        en=("Reinstatement request", f"{who} is asking for their spot back. Open the app to review."),
        ar=("طلب إعادة تسجيل", f"{who} يطلب استرجاع مكانه. افتح التطبيق للمراجعة."),
        data={"screen": "reinstatement", "branch_id": account.branch_id},
        dedupe_key=f"staffreinst:{req.id}",
    )
    return {"message": "Reinstatement request submitted"}


class DeleteAccountBody(PydanticBaseModel):
    password: str


_delete_attempts: dict[int, list[float]] = {}


@router.delete("/account")
async def delete_account(
    body: DeleteAccountBody,
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete the customer's account (Apple App Store requirement).

    Requires password confirmation. Deletes all associated data (devices, notifications,
    verifications, reinstatement requests) and disables the account.
    """
    import time
    from app.utils.auth import verify_password

    # Rate limit: max 5 password attempts per 5 minutes per account
    now = time.time()
    attempts = _delete_attempts.get(account.id, [])
    attempts = [t for t in attempts if now - t < 300]
    if len(attempts) >= 5:
        raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")
    attempts.append(now)
    _delete_attempts[account.id] = attempts

    if not verify_password(body.password, account.password_hash):
        raise HTTPException(status_code=403, detail="Incorrect password")

    account_id = account.id

    # Delete related rows in dependency order
    from app.models.push import DeviceToken, InboxNotification
    from app.models.email_verification import EmailVerification
    from app.models.reinstatement_request import ReinstatementRequest
    from sqlalchemy import delete as sql_delete, update as sql_update

    await db.execute(sql_delete(DeviceToken).where(DeviceToken.account_id == account_id))
    await db.execute(sql_delete(InboxNotification).where(InboxNotification.account_id == account_id))
    await db.execute(sql_delete(EmailVerification).where(EmailVerification.account_id == account_id))
    await db.execute(sql_delete(ReinstatementRequest).where(ReinstatementRequest.account_id == account_id))

    # Nullify notification_log references (column is nullable)
    try:
        from app.models.notification_log import NotificationLog
        await db.execute(
            sql_update(NotificationLog)
            .where(NotificationLog.account_id == account_id)
            .values(account_id=None)
        )
    except Exception:
        pass  # Table may not exist yet

    # Delete the account
    await db.delete(account)
    await db.commit()

    logger.info(f"Account {account_id} deleted by user request")
    return {"message": "Account deleted successfully"}
