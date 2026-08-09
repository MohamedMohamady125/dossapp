"""Customer device registration + in-app notification inbox."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.push import DeviceToken, InboxNotification
from app.routers.deps import get_current_customer
from app.schemas.notification import DeviceTokenIn, NotificationOut, UnreadCountOut

router = APIRouter(prefix="/me", tags=["notifications"])


@router.post("/devices")
async def register_device(
    payload: DeviceTokenIn,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    if payload.platform not in ("android", "ios"):
        raise HTTPException(status_code=400, detail="platform must be 'android' or 'ios'")

    result = await db.execute(select(DeviceToken).where(DeviceToken.token == payload.token))
    device = result.scalar_one_or_none()
    now = datetime.now(timezone.utc)

    if device:
        # Token may move between accounts (shared device / relogin)
        device.account_id = account.id
        device.platform = payload.platform
        device.is_active = True
        device.last_seen_at = now
    else:
        db.add(DeviceToken(
            account_id=account.id,
            token=payload.token,
            platform=payload.platform,
            is_active=True,
            last_seen_at=now,
        ))
    # Update account language preference
    if payload.language in ("en", "ar"):
        account.language = payload.language
        db.add(account)
    await db.commit()
    return {"message": "Device registered"}


@router.delete("/devices/{token}")
async def unregister_device(
    token: str,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(DeviceToken).where(DeviceToken.token == token, DeviceToken.account_id == account.id)
    )
    device = result.scalar_one_or_none()
    if device:
        device.is_active = False
        await db.commit()
    return {"message": "Device unregistered"}


@router.get("/notifications", response_model=list[NotificationOut])
async def list_notifications(
    limit: int = 50,
    offset: int = 0,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(InboxNotification)
        .where(InboxNotification.account_id == account.id)
        .order_by(InboxNotification.created_at.desc(), InboxNotification.id.desc())
        .limit(min(limit, 100))
        .offset(offset)
    )
    return [
        NotificationOut(
            id=n.id, type=n.type, title=n.title, body=n.body,
            data=n.data, is_read=n.is_read, created_at=n.created_at,
        )
        for n in result.scalars().all()
    ]


@router.get("/notifications/unread-count", response_model=UnreadCountOut)
async def unread_count(
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(func.count()).select_from(InboxNotification).where(
            InboxNotification.account_id == account.id,
            InboxNotification.is_read == False,  # noqa: E712
        )
    )
    return UnreadCountOut(unread=result.scalar() or 0)


@router.post("/notifications/{notification_id}/read")
async def mark_read(
    notification_id: int,
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(InboxNotification).where(
            InboxNotification.id == notification_id,
            InboxNotification.account_id == account.id,
        )
    )
    notification = result.scalar_one_or_none()
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    notification.is_read = True
    await db.commit()
    return {"message": "Marked read"}


@router.post("/notifications/read-all")
async def mark_all_read(
    account: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    await db.execute(
        update(InboxNotification)
        .where(InboxNotification.account_id == account.id, InboxNotification.is_read == False)  # noqa: E712
        .values(is_read=True)
    )
    await db.commit()
    return {"message": "All marked read"}
