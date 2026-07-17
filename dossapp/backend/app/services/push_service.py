"""Push notification sending: FCM HTTP v1 + in-app inbox rows.

Uses the raw FCM HTTP v1 API (google-auth + httpx) instead of firebase-admin
to keep serverless cold starts light. If FIREBASE_CREDENTIALS_JSON is not
configured, sends are stub-logged but inbox rows are still written.
"""

import json
import logging
import os
from typing import Optional

import httpx
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.notification_log import NotificationLog
from app.models.push import DeviceToken, InboxNotification, NotificationDedupe

logger = logging.getLogger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

_credentials = None
_project_id: Optional[str] = None


def _load_fcm_credentials():
    """Load (and cache) Firebase service-account credentials.

    Supports a file path (local dev) or inline JSON (Vercel), mirroring
    drive_reader._get_drive_service(). Returns (credentials, project_id)
    or (None, None) when not configured.
    """
    global _credentials, _project_id
    if _credentials is not None:
        return _credentials, _project_id

    creds_value = settings.firebase_credentials_json.strip()
    if not creds_value:
        return None, None

    try:
        from google.oauth2 import service_account

        if os.path.isfile(creds_value):
            with open(creds_value) as f:
                info = json.load(f)
        else:
            try:
                info = json.loads(creds_value)
            except json.JSONDecodeError:
                info = json.loads(creds_value, strict=False)

        _credentials = service_account.Credentials.from_service_account_info(info, scopes=[FCM_SCOPE])
        _project_id = settings.firebase_project_id.strip() or info.get("project_id")
        return _credentials, _project_id
    except Exception as e:
        logger.error(f"Failed to load Firebase credentials: {e}")
        return None, None


def _get_access_token() -> Optional[str]:
    creds, _ = _load_fcm_credentials()
    if creds is None:
        return None
    try:
        if not creds.valid:
            from google.auth.transport.requests import Request
            creds.refresh(Request())
        return creds.token
    except Exception as e:
        logger.error(f"Failed to refresh FCM access token: {e}")
        return None


def push_configured() -> bool:
    creds, _ = _load_fcm_credentials()
    return creds is not None


async def send_fcm(
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
    validate_only: bool = False,
) -> tuple[bool, Optional[str]]:
    """Send one FCM message. Returns (ok, error). error='UNREGISTERED' means dead token."""
    access_token = _get_access_token()
    creds, project_id = _load_fcm_credentials()
    if not access_token or not project_id:
        logger.info(f"[STUB PUSH] to={token[:20]}... title={title!r} body={body!r}")
        return True, None

    message: dict = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
        }
    }
    if data:
        # FCM data values must be strings
        message["message"]["data"] = {k: str(v) for k, v in data.items()}
    if validate_only:
        message["validate_only"] = True

    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                url,
                json=message,
                headers={"Authorization": f"Bearer {access_token}"},
            )
        if resp.status_code == 200:
            return True, None
        try:
            err = resp.json().get("error", {})
            status = err.get("status", "")
            details = err.get("message", resp.text[:200])
        except Exception:
            status, details = "", resp.text[:200]
        if resp.status_code == 404 or status == "NOT_FOUND" or "UNREGISTERED" in (status + details).upper():
            return False, "UNREGISTERED"
        logger.error(f"FCM send failed ({resp.status_code}): {details}")
        return False, details
    except Exception as e:
        logger.error(f"FCM send error: {e}")
        return False, str(e)


async def send_push_to_account(
    db: AsyncSession,
    account_id: int,
    ntype: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
    dedupe_key: Optional[str] = None,
) -> bool:
    """Write an inbox notification + push to all the account's devices.

    Returns False if the dedupe key already exists (already sent).
    """
    if dedupe_key:
        db.add(NotificationDedupe(dedupe_key=dedupe_key))
        try:
            await db.commit()
        except IntegrityError:
            await db.rollback()
            return False

    db.add(InboxNotification(account_id=account_id, type=ntype, title=title, body=body, data=data))
    await db.commit()

    result = await db.execute(
        select(DeviceToken).where(DeviceToken.account_id == account_id, DeviceToken.is_active == True)  # noqa: E712
    )
    tokens = result.scalars().all()
    if not tokens and not push_configured():
        logger.info(f"[STUB PUSH] account={account_id} type={ntype} title={title!r} (no devices)")

    for device in tokens:
        ok, error = await send_fcm(device.token, title, body, data)
        if error == "UNREGISTERED":
            device.is_active = False
        db.add(NotificationLog(
            account_id=account_id,
            channel="push",
            to=device.token[:255],
            status="sent" if ok else "failed",
            error=(error or "")[:500] or None,
            attempts=1,
        ))
    await db.commit()
    return True
