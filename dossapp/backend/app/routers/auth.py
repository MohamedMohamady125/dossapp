"""Auth endpoints — customer + admin login, token refresh, password change, email verification."""

import logging
import re
import secrets
import time
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select, and_, delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.admin_user import AdminUser
from app.models.email_verification import EmailVerification
from app.schemas.auth import (
    CustomerLoginRequest, AdminLoginRequest, ChangePasswordRequest,
    TokenResponse, RefreshRequest, ProfileOut,
    SendVerificationRequest, VerifyCodeRequest, SetPasswordWithEmailRequest,
    ForgotPasswordRequest, ForgotPasswordVerifyRequest, ForgotPasswordResetRequest,
)
from app.utils.auth import (
    verify_password, hash_password, create_access_token,
    create_refresh_token, decode_token, verify_password_async, hash_password_async,
)
from app.routers.deps import (
    get_current_customer, get_current_customer_allow_suspended, get_current_staff,
    get_linked_accounts, USABLE_STATUSES,
)
from app.services.notifications import get_notification_provider

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])

# ── Rate limiting for auth endpoints ──
# Counters live in this worker's memory, so with several workers the real
# ceiling is a small multiple of these numbers. Only FAILED attempts count:
# a branch full of parents signing in correctly must never be locked out.
_failures: dict[str, list[float]] = {}
_RATE_LIMIT_WINDOW = 300   # 5 minutes
_MAX_FAILS_PER_LOGIN = 8   # wrong passwords for one login code / email / username
_MAX_FAILS_PER_IP = 40     # wrong passwords from one phone or network
_MAX_CODE_REQUESTS = 5     # verification emails per address or account


def client_ip(request: Request) -> str:
    """The caller's address. Behind Railway the socket peer is the proxy, so
    read the header the proxy sets."""
    real = request.headers.get("x-real-ip")
    if real:
        return real.strip()
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[-1].strip()
    return request.client.host if request.client else "unknown"


def _recent(key: str, now: float) -> list[float]:
    hits = [t for t in _failures.get(key, []) if now - t < _RATE_LIMIT_WINDOW]
    if hits:
        _failures[key] = hits
    else:
        _failures.pop(key, None)
    return hits


def _too_many(key: str, limit: int) -> bool:
    return len(_recent(key, time.time())) >= limit


def _record(key: str) -> None:
    now = time.time()
    if len(_failures) > 20000:  # never let the table grow without bound
        for k in list(_failures):
            _recent(k, now)
    _failures[key] = _recent(key, now) + [now]


def _login_keys(kind: str, identifier: str, request: Request) -> list[tuple[str, int]]:
    return [
        (f"{kind}:id:{identifier.strip().lower()[:120]}", _MAX_FAILS_PER_LOGIN),
        (f"{kind}:ip:{client_ip(request)}", _MAX_FAILS_PER_IP),
    ]


def _check_login_allowed(kind: str, identifier: str, request: Request) -> None:
    for key, limit in _login_keys(kind, identifier, request):
        if _too_many(key, limit):
            raise HTTPException(status_code=429, detail="Too many login attempts. Try again in a few minutes.")


def _record_login_failure(kind: str, identifier: str, request: Request) -> None:
    for key, _ in _login_keys(kind, identifier, request):
        _record(key)


def _limit_code_requests(key: str) -> None:
    if _too_many(key, _MAX_CODE_REQUESTS):
        raise HTTPException(status_code=429, detail="Too many codes requested. Try again in a few minutes.")
    _record(key)


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
            await db.commit()  # the error below rolls the request back
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Identity mismatch — the athlete at this number has changed. Contact admin.",
            )


async def build_profiles(db: AsyncSession, current: Account) -> list[ProfileOut]:
    """The swimmers the parent of `current` can open, with `current` flagged."""
    from app.models.branch import Branch

    linked = await get_linked_accounts(db, current)
    result = await db.execute(select(Branch.id, Branch.display_name))
    branch_names = {row[0]: row[1] for row in result.all()}
    return [
        ProfileOut(
            account_id=a.id,
            athlete_number=a.athlete_number,
            name=a.name_at_creation,
            branch_id=a.branch_id,
            branch_name=branch_names.get(a.branch_id, ""),
            login_code=a.login_code,
            is_current=a.id == current.id,
        )
        for a in linked
    ]


def customer_token_data(account: Account) -> dict:
    return {
        "sub": str(account.id),
        "role": "customer",
        "branch_id": account.branch_id,
        "athlete_number": account.athlete_number,
    }


@router.post("/customer/login", response_model=TokenResponse)
async def customer_login(req: CustomerLoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    """Sign in with the login code or the verified email, plus the password."""
    identifier = req.login_code.strip()
    _check_login_allowed("customer", identifier, request)
    invalid = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    if "@" in identifier:
        # Email: a parent may have several swimmers on it. The password of any
        # of them proves who they are; they then pick which swimmer to open.
        result = await db.execute(
            select(Account)
            .where(func.lower(Account.email) == identifier.lower())
            .order_by(Account.last_login_at.desc().nullslast(), Account.id)
        )
        candidates = [a for a in result.scalars().all() if a.status in USABLE_STATUSES]
        # Candidates are ordered most recently used first, so the first match
        # is the swimmer to open. Hashing runs off the event loop.
        account = None
        for candidate in candidates:
            if await verify_password_async(req.password, candidate.password_hash):
                account = candidate
                break
        if not account:
            _record_login_failure("customer", identifier, request)
            raise invalid
    else:
        result = await db.execute(
            select(Account).where(func.upper(Account.login_code) == identifier.upper())
        )
        account = result.scalars().first()
        if not account or not await verify_password_async(req.password, account.password_hash):
            _record_login_failure("customer", identifier, request)
            raise invalid

    if account.status == "disabled":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account disabled")

    if account.status == "identity_mismatch":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Identity mismatch — contact admin")

    # Run identity guard on every login
    await _run_identity_guard(account, db)

    account.last_login_at = datetime.now(timezone.utc)

    token_data = customer_token_data(account)
    return TokenResponse(
        access_token=create_access_token(token_data),
        refresh_token=create_refresh_token(token_data),
        must_change_password=account.must_change_password,
        profiles=await build_profiles(db, account),
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
    return f"{secrets.randbelow(900000) + 100000}"


_MAX_CODE_ATTEMPTS = 5
# After a code is verified, the follow-up step (set the password) must happen
# within this long of the code's expiry, or the parent starts again.
_VERIFIED_GRACE = timedelta(minutes=20)


async def _check_code(db: AsyncSession, verification, code: str) -> None:
    """Reject a missing, expired, over-tried or wrong code.

    A wrong guess is committed before the error is raised: the request's
    transaction is rolled back on any error, which used to wipe the counter
    and allowed unlimited guesses.
    """
    if not verification:
        raise HTTPException(status_code=400, detail="No pending verification found")
    if verification.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Verification code expired")
    if (verification.attempts or 0) >= _MAX_CODE_ATTEMPTS:
        raise HTTPException(status_code=400, detail="Too many failed attempts. Request a new code.")
    if not secrets.compare_digest(str(verification.code), str(code).strip()):
        verification.attempts = (verification.attempts or 0) + 1
        db.add(verification)
        await db.commit()
        raise HTTPException(status_code=400, detail="Invalid verification code")


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
    _limit_code_requests(f"verify:account:{account.id}")

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
        ).order_by(EmailVerification.id.desc()).limit(1)
    )
    verification = result.scalars().first()
    await _check_code(db, verification, req.code)

    verification.verified = True
    account.email = req.email.strip().lower()
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
    # First-time setup only. Afterwards the password changes in Settings,
    # where the current password is required.
    if not account.must_change_password:
        raise HTTPException(status_code=403, detail="Use profile settings to change your password")

    # Check for a verified EmailVerification for this account
    result = await db.execute(
        select(EmailVerification).where(
            and_(
                EmailVerification.account_id == account.id,
                EmailVerification.email == req.email,
                EmailVerification.purpose == "onboarding",
                EmailVerification.verified == True,
            )
        ).order_by(EmailVerification.id.desc()).limit(1)
    )
    verification = result.scalars().first()

    if not verification:
        raise HTTPException(status_code=400, detail="Email not verified. Complete verification first.")

    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    account.password_hash = await hash_password_async(req.new_password)
    account.must_change_password = False
    account.email = req.email.strip().lower()
    db.add(account)

    return {"message": "Account setup complete"}


# ── Helper: find account (customer or staff) by email ──
async def _find_account_by_email(db: AsyncSession, email: str):
    """Look up a customer Account or AdminUser by email. Returns (account, account_type)."""
    result = await db.execute(
        select(Account).where(func.lower(Account.email) == email).order_by(Account.last_login_at.desc().nullslast()).limit(1)
    )
    account = result.scalar_one_or_none()
    if account:
        return account, "customer"

    result = await db.execute(
        select(AdminUser).where(AdminUser.email == email).order_by(AdminUser.last_login_at.desc().nullslast()).limit(1)
    )
    admin = result.scalar_one_or_none()
    if admin:
        return admin, "staff"

    return None, None


# ── Forgot password: send code ──
@router.post("/forgot-password/send-code")
async def forgot_password_send_code(
    req: ForgotPasswordRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    generic_msg = "If an account exists with this email, a verification code has been sent"

    # Rate limit: max 5 code requests per email per 15 minutes
    _limit_code_requests(f"forgot:email:{req.email.strip().lower()[:120]}")
    _limit_code_requests(f"forgot:ip:{client_ip(request)}")

    account, account_type = await _find_account_by_email(db, req.email.strip().lower())
    if not account:
        return {"message": generic_msg}

    code = _generate_code()
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)

    # Delete every earlier forgot-password code for this email, used or not
    await db.execute(
        delete(EmailVerification).where(
            and_(
                EmailVerification.email == req.email.strip().lower(),
                EmailVerification.purpose == "forgot_password",
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
        ).order_by(EmailVerification.id.desc()).limit(1)
    )
    verification = ver_result.scalars().first()
    await _check_code(db, verification, req.code)

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
        ).order_by(EmailVerification.id.desc()).limit(1)
    )
    verification = ver_result.scalars().first()

    if not verification:
        raise HTTPException(status_code=400, detail="Email not verified. Complete verification first.")

    # The reset must carry the same code that was verified, and soon after:
    # knowing only the email is not enough.
    now = datetime.now(timezone.utc)
    if (verification.attempts or 0) >= _MAX_CODE_ATTEMPTS or verification.expires_at + _VERIFIED_GRACE < now:
        raise HTTPException(status_code=400, detail="Verification expired. Request a new code.")
    if not secrets.compare_digest(str(verification.code), str(req.code).strip()):
        verification.attempts = (verification.attempts or 0) + 1
        db.add(verification)
        await db.commit()
        raise HTTPException(status_code=400, detail="Invalid verification code")

    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    # Find the account (customer or staff) by email and update password
    account, account_type = await _find_account_by_email(db, email)
    if not account:
        raise HTTPException(status_code=400, detail="Account not found")

    # A parent with several swimmers has one account per swimmer on the same
    # email. Reset them together, so the new password opens all of them
    # instead of whichever one happened to be used last.
    targets = await get_linked_accounts(db, account) if account_type == "customer" else [account]
    new_hash = await hash_password_async(req.new_password)
    for target in targets:
        target.password_hash = new_hash
        if hasattr(target, 'must_change_password'):
            target.must_change_password = False
        db.add(target)

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
    _check_login_allowed("staff", req.username, request)
    result = await db.execute(select(AdminUser).where(AdminUser.username == req.username))
    admin = result.scalar_one_or_none()

    if not admin or not await verify_password_async(req.password, admin.password_hash):
        _record_login_failure("staff", req.username, request)
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
            if not account or account.status == "disabled":
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account not found or disabled")
            if account.status == "identity_mismatch":
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Identity mismatch — contact admin")
            await _run_identity_guard(account, db)
    elif payload.get("role") in ("admin", "assistant", "coach"):
        result = await db.execute(select(AdminUser).where(AdminUser.id == int(payload.get("sub") or 0)))
        staff = result.scalar_one_or_none()
        if not staff or not staff.is_active or staff.role != payload.get("role"):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")
    else:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

    token_data = {k: v for k, v in payload.items() if k not in ("exp", "type")}
    return TokenResponse(
        access_token=create_access_token(token_data),
        refresh_token=create_refresh_token(token_data),
    )
