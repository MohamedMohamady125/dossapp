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

# Payment reminder days: 25, 27, 29, 1 (every 2 days from the 25th until the 1st)
PAYMENT_REMINDER_DAYS = {25, 27, 29, 1}
SPOT_LOST_DAY = 2


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
    """Send unpaid reminders — on days 25, 27, 29, 1 (every 2 days)."""
    _authorize(authorization)

    today = datetime.now().day
    if not force and today not in PAYMENT_REMINDER_DAYS:
        return {"skipped": True, "reason": f"Day {today} not in reminder days {sorted(PAYMENT_REMINDER_DAYS)}"}

    from app.services.push_triggers import send_payment_reminders

    source = _get_roster_source()
    rosters = await source.get_all_rosters()

    async with async_session() as db:
        sent = await send_payment_reminders(db, rosters)

    logger.info(f"Cron payment reminders: sent={sent}")
    return {"branches": len(rosters), "sent": sent}


@router.get("/spot-lost")
async def cron_spot_lost(
    force: bool = False,
    authorization: Optional[str] = Header(None),
):
    """On the 2nd of month: suspend unpaid athletes and notify them."""
    _authorize(authorization)

    today = datetime.now().day
    if not force and today != SPOT_LOST_DAY:
        return {"skipped": True, "reason": f"Day {today} is not day {SPOT_LOST_DAY}"}

    from app.services.push_triggers import send_spot_lost_notifications

    source = _get_roster_source()
    rosters = await source.get_all_rosters()

    async with async_session() as db:
        sent = await send_spot_lost_notifications(db, rosters)

    logger.info(f"Cron spot-lost: sent={sent}")
    return {"branches": len(rosters), "sent": sent}
