"""Auth endpoints — customer + admin login, token refresh, password change."""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.admin_user import AdminUser
from app.schemas.auth import (
    CustomerLoginRequest, AdminLoginRequest, ChangePasswordRequest,
    TokenResponse, RefreshRequest,
)
from app.utils.auth import (
    verify_password, hash_password, create_access_token,
    create_refresh_token, decode_token,
)
from app.routers.deps import get_current_customer

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
    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    account.password_hash = hash_password(req.new_password)
    account.must_change_password = False
    db.add(account)
    return {"message": "Password changed successfully"}


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

    return TokenResponse(
        access_token=create_access_token(token_data),
        refresh_token=create_refresh_token(token_data),
    )


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
