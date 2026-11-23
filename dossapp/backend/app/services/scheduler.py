"""Built-in daily scheduler for payment reminders and spot-lost.

These two jobs used to depend on an outside cron service calling /cron/*,
and none was ever set up, so they never ran. This loop runs inside the app
instead: it wakes every few minutes and, once it is past the send hour in
Egypt, runs whatever is due that day.

The server runs several worker processes, each with its own copy of this
loop. Before running a job a worker claims it by inserting a row with a
unique key (job name + date); only the worker whose insert succeeds runs it.
If the job fails, the claim is released so a later tick tries again. The
jobs are also safe to repeat: every push is deduped per swimmer.
"""

import asyncio
import logging

from sqlalchemy import delete
from sqlalchemy.exc import IntegrityError

from app.config import settings
from app.database import async_session
from app.models.push import NotificationDedupe
from app.services.push_triggers import (
    local_now,
    send_payment_reminders,
    send_spot_lost_notifications,
)

logger = logging.getLogger(__name__)

# Unpaid reminders go out on these days of the month; on the 2nd, swimmers
# who still have not paid lose their spot.
PAYMENT_REMINDER_DAYS = {25, 27, 29, 1}
SPOT_LOST_DAY = 2

CHECK_EVERY_SECONDS = 600


def jobs_due(day: int) -> list[str]:
    jobs = []
    if day in PAYMENT_REMINDER_DAYS:
        jobs.append("payment_reminders")
    if day == SPOT_LOST_DAY:
        jobs.append("spot_lost")
    return jobs


async def _claim(key: str) -> bool:
    """True if this worker is the one that gets to run the job."""
    async with async_session() as db:
        db.add(NotificationDedupe(dedupe_key=key))
        try:
            await db.commit()
            return True
        except IntegrityError:
            await db.rollback()
            return False


async def _release(key: str) -> None:
    async with async_session() as db:
        await db.execute(delete(NotificationDedupe).where(NotificationDedupe.dedupe_key == key))
        await db.commit()


async def run_job(name: str, rosters: dict) -> int:
    async with async_session() as db:
        if name == "payment_reminders":
            return await send_payment_reminders(db, rosters)
        if name == "spot_lost":
            return await send_spot_lost_notifications(db, rosters)
    raise ValueError(f"Unknown job {name}")


async def run_due_jobs(get_rosters) -> dict[str, int]:
    """Run today's jobs that no worker has run yet. Returns {job: pushes sent}."""
    now = local_now()
    if now.hour < settings.daily_jobs_hour:
        return {}

    results: dict[str, int] = {}
    for name in jobs_due(now.day):
        key = f"job:{name}:{now.strftime('%Y-%m-%d')}"
        if not await _claim(key):
            continue
        try:
            rosters = await get_rosters()
            if not rosters:
                raise RuntimeError("no rosters loaded yet")
            results[name] = await run_job(name, rosters)
            logger.info(f"Daily job {name}: sent={results[name]} branches={len(rosters)}")
        except BaseException as e:
            # BaseException on purpose: a deploy cancels this task mid-job, and
            # a claim left behind would stop every worker from finishing today.
            # Re-running is safe, each push is deduped per swimmer per day.
            logger.error(f"Daily job {name} failed, will retry: {e!r}")
            try:
                await asyncio.shield(_release(key))
            except BaseException as release_error:
                logger.error(f"Could not release claim {key}: {release_error!r}")
            if not isinstance(e, Exception):
                raise
    return results


async def run_daily_jobs(get_rosters) -> None:
    """Background loop. `get_rosters` returns {branch_id: BranchRoster}."""
    if not settings.daily_jobs_enabled:
        logger.info("Daily jobs are disabled (DAILY_JOBS_ENABLED=false)")
        return
    logger.info(f"Daily jobs scheduler started (runs after {settings.daily_jobs_hour}:00 Egypt time)")
    while True:
        try:
            await run_due_jobs(get_rosters)
        except Exception as e:
            logger.error(f"Daily jobs loop error: {e}")
        await asyncio.sleep(CHECK_EVERY_SECONDS)
