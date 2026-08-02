"""Cron endpoints — invoked by Vercel Cron (Authorization: Bearer $CRON_SECRET).

An admin JWT is also accepted so triggers can be run manually from the app/API.
"""

import hmac
import logging
from datetime import datetime

from fastapi import APIRouter, Header, HTTPException
from typing import Optional

from app.config import settings
from app.database import async_session
from app.utils.auth import decode_token

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/cron", tags=["cron"])


def _authorize(authorization: Optional[str]):
    token = (authorization or "").removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing authorization")

    if settings.cron_secret and hmac.compare_digest(token, settings.cron_secret):
        return

    payload = decode_token(token)
    if payload and payload.get("type") == "access" and payload.get("role") == "admin":
        return

    raise HTTPException(status_code=401, detail="Invalid cron credentials")


def _get_roster_source():
    from app.main import roster_source
    return roster_source


@router.get("/notifications")
async def cron_notifications(force: bool = False, authorization: Optional[str] = Header(None)):
    """Refresh rosters and run schedule-change + missed-session triggers."""
    _authorize(authorization)
    from app.services.push_triggers import run_roster_triggers

    source = _get_roster_source()
    await source.refresh_all(force=force)
    rosters = await source.get_all_rosters()

    totals = {"schedule": 0, "missed": 0}
    for branch_id, roster in rosters.items():
        async with async_session() as db:
            counts = await run_roster_triggers(roster, db)
        totals["schedule"] += counts["schedule"]
        totals["missed"] += counts["missed"]

    logger.info(f"Cron notifications: {totals}")
    return {"branches": len(rosters), "sent": totals}


@router.get("/payment-reminders")
async def cron_payment_reminders(
    force: bool = False,
    authorization: Optional[str] = Header(None),
):
    """Send unpaid reminders — only on the configured day of month (default 25th)."""
    _authorize(authorization)

    if not force and datetime.now().day != settings.payment_reminder_day:
        return {"skipped": True, "reason": f"Not day {settings.payment_reminder_day}"}

    from app.services.push_triggers import send_payment_reminders

    source = _get_roster_source()
    rosters = await source.get_all_rosters()

    async with async_session() as db:
        sent = await send_payment_reminders(db, rosters)

    logger.info(f"Cron payment reminders: sent={sent}")
    return {"branches": len(rosters), "sent": sent}
