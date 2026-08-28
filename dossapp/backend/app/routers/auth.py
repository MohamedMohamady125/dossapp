"""Auth endpoints — customer + admin login, token refresh, password change, email verification."""

import logging
import random
import re
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select, and_, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.admin_user import AdminUser
from app.models.email_verification import EmailVerification
from app.schemas.auth import (
    CustomerLoginRequest, AdminLoginRequest, ChangePasswordRequest,
    TokenResponse, RefreshRequest,
    SendVerificationRequest, VerifyCodeRequest, SetPasswordWithEmailRequest,
    ForgotPasswordRequest, ForgotPasswordVerifyRequest, ForgotPasswordResetRequest,
)
from app.utils.auth import (
    verify_password, hash_password, create_access_token,
    create_refresh_token, decode_token,
)
from app.routers.deps import get_current_customer, get_current_customer_allow_suspended, get_current_staff
from app.services.notifications import get_notification_provider

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])

# ── Simple in-memory rate limiter for auth endpoints ──
_login_attempts: dict[str, list[float]] = {}
_RATE_LIMIT_WINDOW = 300  # 5 minutes
_RATE_LIMIT_MAX = 10  # max attempts per window


def _check_rate_limit(key: str):
    """Raise 429 if too many login attempts from this key."""
    import time
    now = time.time()
    attempts = _login_attempts.get(key, [])
    # Prune old entries
    attempts = [t for t in attempts if now - t < _RATE_LIMIT_WINDOW]
    if len(attempts) >= _RATE_LIMIT_MAX:
        raise HTTPException(status_code=429, detail="Too many login attempts. Try again later.")
    attempts.append(now)
    _login_attempts[key] = attempts


async def _run_identity_guard(account: Account, db: AsyncSession):
    """Check if the athlete in Excel still matches the account's identity snapshot."""
    from app.main import roster_source
    roster = await roster_source.get_branch_roster(account.branch_id)
    if not roster:
        return  # Can't verify — Excel not loaded; don't block

    athlete = next((a for a in roster.athletes if a.athlete_number == account.athlete_number), None)
    if not athlete:
        return  # Absent from roster — handled as "no enrollment", not a mismatch

    # Compare name (case-insensitive, stripped)
    excel_name = (athlete.name or "").strip().lower()
    stored_name = (account.name_at_creation or "").strip().lower()

    if stored_name and excel_name and excel_name != stored_name:
        # Check if it's a clear mismatch (not just a minor formatting diff)
        # Use simple containment as a fuzzy check
        if stored_name not in excel_name and excel_name not in stored_name:
            logger.warning(
                f"Identity mismatch: account {account.id} ({account.branch_id}, {account.athlete_number}) "
                f"— stored='{account.name_at_creation}', excel='{athlete.name}'"
            )
            account.status = "identity_mismatch"
            db.add(account)
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Identity mismatch — the athlete at this number has changed. Contact admin.",
            )


@router.post("/customer/login", response_model=TokenResponse)
async def customer_login(req: CustomerLoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    _check_rate_limit(f"customer:{request.client.host if request.client else 'unknown'}")

    result = await db.execute(select(Account).where(Account.login_code == req.login_code))
    account = result.scalar_one_or_none()

    if not account or not verify_password(req.password, account.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    if account.status == "disabled":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account disabled")

    if account.status == "identity_mismatch":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Identity mismatch — contact admin")

    # Run identity guard on every login
    await _run_identity_guard(account, db)

    account.last_login_at = datetime.now(timezone.utc)

    token_data = {
        "sub": str(account.id),
        "role": "customer",
        "branch_id": account.branch_id,
        "athlete_number": account.athlete_number,
    }

    return TokenResponse(
        access_token=create_access_token(token_data),
        refresh_token=create_refresh_token(token_data),
        must_change_password=account.must_change_password,
    )


@router.post("/customer/change-password")
async def customer_change_password(
    req: ChangePasswordRequest,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    # This endpoint is only for forced first-time password setup (onboarding).
    # Voluntary changes use PUT /me/password which verifies old password.
    if not account.must_change_password:
        raise HTTPException(status_code=403, detail="Use profile settings to change your password")

    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    account.password_hash = hash_password(req.new_password)
    account.must_change_password = False
    db.add(account)
    return {"message": "Password changed successfully"}


# ── Email validation helper ──
_EMAIL_RE = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")


def _validate_email(email: str):
    if not _EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="Invalid email format")


def _generate_code() -> str:
    return f"{random.randint(100000, 999999)}"


async def _send_verification_email(email: str, code: str):
    provider = get_notification_provider()
    logger.info(f"Sending verification email to {email} via {type(provider).__name__}")
    result = await provider.send_email(
        email,
        "Aquathletic - Verification Code",
        f"<p>Your verification code is: <strong>{code}</strong></p><p>This code expires in 10 minutes.</p>",
    )
    logger.info(f"Verification email result: {result}")


# ── Onboarding: send verification code ──
@router.post("/customer/send-verification")
async def customer_send_verification(
    req: SendVerificationRequest,
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    _validate_email(req.email)

    code = _generate_code()
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)

    # Delete any previous unverified codes for this account + purpose
    await db.execute(
        delete(EmailVerification).where(
            and_(
                EmailVerification.account_id == account.id,
                EmailVerification.purpose == "onboarding",
                EmailVerification.verified == False,
            )
        )
    )

    verification = EmailVerification(
        account_id=account.id,
        email=req.email,
        code=code,
        purpose="onboarding",
        expires_at=expires,
    )
    db.add(verification)
    await db.flush()

    await _send_verification_email(req.email, code)

    return {"message": "Verification code sent"}


# ── Onboarding: verify the code ──
@router.post("/customer/verify-code")
async def customer_verify_code(
    req: VerifyCodeRequest,
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(EmailVerification).where(
            and_(
                EmailVerification.account_id == account.id,
                EmailVerification.email == req.email,
                EmailVerification.purpose == "onboarding",
                EmailVerification.verified == False,
            )
        ).order_by(EmailVerification.created_at.desc())
    )
    verification = result.scalar_one_or_none()

    if not verification:
        raise HTTPException(status_code=400, detail="No pending verification found")

    if verification.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Verification code expired")

    if verification.attempts >= 5:
        raise HTTPException(status_code=400, detail="Too many failed attempts. Request a new code.")

    if verification.code != req.code:
        verification.attempts += 1
        db.add(verification)
        raise HTTPException(status_code=400, detail="Invalid verification code")

    verification.verified = True
    account.email = req.email
    db.add(verification)
    db.add(account)

    return {"verified": True}


# ── Onboarding: complete (set password after email verified) ──
@router.post("/customer/complete-onboarding")
async def customer_complete_onboarding(
    req: SetPasswordWithEmailRequest,
    account: Account = Depends(get_current_customer_allow_suspended),
    db: AsyncSession = Depends(get_db),
):
    # Check for a verified EmailVerification for this account
    result = await db.execute(
        select(EmailVerification).where(
            and_(
                EmailVerification.account_id == account.id,
                EmailVerification.email == req.email,
                EmailVerification.purpose == "onboarding",
                EmailVerification.verified == True,
            )
        )
    )
    verification = result.scalar_one_or_none()

    if not verification:
        raise HTTPException(status_code=400, detail="Email not verified. Complete verification first.")

    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    account.password_hash = hash_password(req.new_password)
    account.must_change_password = False
    account.email = req.email
    db.add(account)

    return {"message": "Account setup complete"}


# ── Helper: find account (customer or staff) by email ──
async def _find_account_by_email(db: AsyncSession, email: str):
    """Look up a customer Account or AdminUser by email. Returns (account, account_type)."""
    result = await db.execute(select(Account).where(Account.email == email))
    account = result.scalar_one_or_none()
    if account:
        return account, "customer"

    result = await db.execute(select(AdminUser).where(AdminUser.email == email))
    admin = result.scalar_one_or_none()
    if admin:
        return admin, "staff"

    return None, None


# ── Forgot password: send code ──
@router.post("/forgot-password/send-code")
async def forgot_password_send_code(
    req: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
):
    generic_msg = "If an account exists with this email, a verification code has been sent"

    # Rate limit: max 5 code requests per email per 15 minutes
    rate_key = f"forgot:{req.email.lower()}"
    _check_rate_limit(rate_key)

    account, account_type = await _find_account_by_email(db, req.email.strip().lower())
    if not account:
        return {"message": generic_msg}

    code = _generate_code()
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)

    # Delete any previous unverified forgot-password codes for this email
    await db.execute(
        delete(EmailVerification).where(
            and_(
                EmailVerification.email == req.email.strip().lower(),
                EmailVerification.purpose == "forgot_password",
                EmailVerification.verified == False,
            )
        )
    )

    verification = EmailVerification(
        account_id=account.id if account_type == "customer" else None,
        email=req.email.strip().lower(),
        code=code,
        purpose="forgot_password",
        expires_at=expires,
    )
    db.add(verification)
    await db.flush()

    await _send_verification_email(req.email.strip(), code)

    return {"message": generic_msg}


# ── Forgot password: verify code ──
@router.post("/forgot-password/verify")
async def forgot_password_verify(
    req: ForgotPasswordVerifyRequest,
    db: AsyncSession = Depends(get_db),
):
    email = req.email.strip().lower()

    ver_result = await db.execute(
        select(EmailVerification).where(
            and_(
                EmailVerification.email == email,
                EmailVerification.purpose == "forgot_password",
                EmailVerification.verified == False,
            )
        ).order_by(EmailVerification.created_at.desc())
    )
    verification = ver_result.scalar_one_or_none()

    if not verification:
        raise HTTPException(status_code=400, detail="No pending verification found")

    if verification.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Verification code expired")

    if verification.attempts >= 5:
        raise HTTPException(status_code=400, detail="Too many failed attempts. Request a new code.")

    if verification.code != req.code:
        verification.attempts += 1
        db.add(verification)
        raise HTTPException(status_code=400, detail="Invalid verification code")

    verification.verified = True
    db.add(verification)

    return {"verified": True}


# ── Forgot password: reset password ──
@router.post("/forgot-password/reset")
async def forgot_password_reset(
    req: ForgotPasswordResetRequest,
    db: AsyncSession = Depends(get_db),
):
    email = req.email.strip().lower()

    # Check for a verified forgot-password verification
    ver_result = await db.execute(
        select(EmailVerification).where(
            and_(
                EmailVerification.email == email,
                EmailVerification.purpose == "forgot_password",
                EmailVerification.verified == True,
            )
        )
    )
    verification = ver_result.scalar_one_or_none()

    if not verification:
        raise HTTPException(status_code=400, detail="Email not verified. Complete verification first.")

    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    # Find the account (customer or staff) by email and update password
    account, account_type = await _find_account_by_email(db, email)
    if not account:
        raise HTTPException(status_code=400, detail="Account not found")

    account.password_hash = hash_password(req.new_password)
    if hasattr(account, 'must_change_password'):
        account.must_change_password = False
    db.add(account)

    # Clean up used verification
    await db.execute(
        delete(EmailVerification).where(
            and_(
                EmailVerification.email == email,
                EmailVerification.purpose == "forgot_password",
            )
        )
    )

    return {"message": "Password reset successfully"}


@router.post("/admin/login", response_model=TokenResponse)
async def admin_login(req: AdminLoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    _check_rate_limit(f"admin:{request.client.host if request.client else 'unknown'}")
    result = await db.execute(select(AdminUser).where(AdminUser.username == req.username))
    admin = result.scalar_one_or_none()

    if not admin or not verify_password(req.password, admin.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    if not admin.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account inactive")

    admin.last_login_at = datetime.now(timezone.utc)

    token_data = {
        "sub": str(admin.id),
        "role": admin.role,
        "branch_id": admin.assigned_branch_id,
    }
    if admin.role == "coach":
        token_data["coach_name"] = admin.coach_name

    return TokenResponse(
        access_token=create_access_token(token_data),
        refresh_token=create_refresh_token(token_data),
        must_change_password=admin.must_change_password or False,
    )


@router.post("/staff/change-password")
async def staff_change_password(
    req: ChangePasswordRequest,
    user: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    user.password_hash = hash_password(req.new_password)
    user.must_change_password = False
    db.add(user)
    return {"message": "Password changed successfully"}


@router.post("/staff/update-password")
async def staff_update_password(
    req: Request,
    user: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    """Change staff password with old password verification (voluntary change)."""
    body = await req.json()
    old_password = body.get("old_password", "")
    new_password = body.get("new_password", "")

    if not verify_password(old_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters")

    user.password_hash = hash_password(new_password)
    db.add(user)
    return {"message": "Password changed successfully"}


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(req: RefreshRequest, db: AsyncSession = Depends(get_db)):
    payload = decode_token(req.refresh_token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

    # Run identity guard on customer token refresh
    if payload.get("role") == "customer":
        account_id = payload.get("sub")
        if account_id:
            result = await db.execute(select(Account).where(Account.id == int(account_id)))
            account = result.scalar_one_or_none()
            if account:
                if account.status == "identity_mismatch":
                    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Identity mismatch — contact admin")
                await _run_identity_guard(account, db)

    token_data = {k: v for k, v in payload.items() if k not in ("exp", "type")}
    return TokenResponse(
        access_token=create_access_token(token_data),
        refresh_token=create_refresh_token(token_data),
    )
