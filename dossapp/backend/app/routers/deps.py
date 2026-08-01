"""Shared dependencies for route handlers — auth extraction, scope enforcement."""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.admin_user import AdminUser
from app.utils.auth import decode_token

security = HTTPBearer()


async def get_current_customer(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> Account:
    payload = decode_token(credentials.credentials)
    if not payload or payload.get("type") != "access" or payload.get("role") != "customer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    account_id = payload.get("sub")
    result = await db.execute(select(Account).where(Account.id == int(account_id)))
    account = result.scalar_one_or_none()

    if not account or account.status == "disabled":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account not found or disabled")

    if account.status == "identity_mismatch":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Identity mismatch — contact admin")

    if account.status == "suspended":
        raise HTTPException(status_code=423, detail="Account suspended")

    return account


async def get_current_customer_allow_suspended(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> Account:
    """Like get_current_customer but allows suspended accounts through."""
    payload = decode_token(credentials.credentials)
    if not payload or payload.get("type") != "access" or payload.get("role") != "customer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    account_id = payload.get("sub")
    result = await db.execute(select(Account).where(Account.id == int(account_id)))
    account = result.scalar_one_or_none()

    if not account or account.status == "disabled":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account not found or disabled")

    if account.status == "identity_mismatch":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Identity mismatch — contact admin")

    return account


async def get_current_admin(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> AdminUser:
    payload = decode_token(credentials.credentials)
    if not payload or payload.get("type") != "access" or payload.get("role") not in ("admin", "assistant"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    admin_id = payload.get("sub")
    result = await db.execute(select(AdminUser).where(AdminUser.id == int(admin_id)))
    admin = result.scalar_one_or_none()

    if not admin or not admin.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin not found or inactive")

    return admin


async def get_current_coach(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> AdminUser:
    payload = decode_token(credentials.credentials)
    if not payload or payload.get("type") != "access" or payload.get("role") != "coach":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    coach_id = payload.get("sub")
    result = await db.execute(select(AdminUser).where(AdminUser.id == int(coach_id)))
    coach = result.scalar_one_or_none()

    if not coach or not coach.is_active or coach.role != "coach":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Coach not found or inactive")

    return coach


async def get_current_staff(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> AdminUser:
    """Any active AdminUser — admin, assistant, or coach."""
    payload = decode_token(credentials.credentials)
    if not payload or payload.get("type") != "access" or payload.get("role") not in ("admin", "assistant", "coach"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user_id = payload.get("sub")
    result = await db.execute(select(AdminUser).where(AdminUser.id == int(user_id)))
    user = result.scalar_one_or_none()

    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

    return user


def enforce_branch_scope(admin: AdminUser, branch_id: int):
    """Enforce that an assistant can only access their assigned branch."""
    if admin.role == "admin":
        return  # Admin has access to all branches
    if admin.assigned_branch_id != branch_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this branch")
