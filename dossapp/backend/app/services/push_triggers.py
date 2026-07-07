"""Notification triggers driven by parsed roster data.

1. Schedule entered/changed — per-athlete schedule hash vs stored snapshot.
2. Missed 2 sessions — last 2 recorded attendance marks are both Absent.
3. Payment reminder — unpaid for current period on the reminder day.

All triggers are idempotent: send_push_to_account dedupes via NotificationDedupe,
so it's safe to run them repeatedly (serverless lazy loads, crons, dev loop).
"""

import hashlib
import logging
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.payment import Payment
from app.models.push import ScheduleSnapshot
from app.services.push_service import send_push_to_account
from app.services.roster_source import Athlete, BranchRoster

logger = logging.getLogger(__name__)


def _schedule_hash(athlete: Athlete) -> str:
    parts = sorted((s.coach or "", s.time_block or "", s.day_pair or "") for s in athlete.schedule)
    return hashlib.sha256(repr(parts).encode()).hexdigest()


def _schedule_json(athlete: Athlete) -> list[dict]:
    return [
        {"coach": s.coach, "time_block": s.time_block, "day_pair": s.day_pair}
        for s in athlete.schedule
    ]


def _schedule_body(athlete: Athlete) -> str:
    lines = []
    for s in athlete.schedule:
        part = s.day_pair or "Days TBD"
        if s.time_block:
            part += f" {s.time_block}"
        if s.coach:
            part += f" with Coach {s.coach}"
        lines.append(part)
    body = f"{athlete.name}'s schedule: " + "; ".join(lines) if lines else f"{athlete.name}'s schedule was updated."
    return body[:1000]


async def _active_accounts(db: AsyncSession, branch_id: int) -> dict[int, Account]:
    result = await db.execute(
        select(Account).where(Account.branch_id == branch_id, Account.status == "active")
    )
    return {a.athlete_number: a for a in result.scalars().all()}


async def check_schedule_changes(roster: BranchRoster, db: AsyncSession) -> int:
    """Notify customers whose athlete's schedule appeared or changed. Returns sends."""
    accounts = await _active_accounts(db, roster.branch_id)

    result = await db.execute(
        select(ScheduleSnapshot).where(ScheduleSnapshot.branch_id == roster.branch_id)
    )
    snapshots = {s.athlete_number: s for s in result.scalars().all()}

    # First run for this branch: seed snapshots silently (no notification blast)
    seed_mode = len(snapshots) == 0

    sent = 0
    for athlete in roster.athletes:
        new_hash = _schedule_hash(athlete)
        snap = snapshots.get(athlete.athlete_number)

        if snap is None:
            if not athlete.schedule:
                continue
            db.add(ScheduleSnapshot(
                branch_id=roster.branch_id,
                athlete_number=athlete.athlete_number,
                schedule_hash=new_hash,
                schedule_json=_schedule_json(athlete),
            ))
            await db.commit()
            if seed_mode:
                continue
            account = accounts.get(athlete.athlete_number)
            if account:
                ok = await send_push_to_account(
                    db, account.id, "schedule_change",
                    "Schedule added",
                    _schedule_body(athlete),
                    data={"screen": "schedule"},
                    dedupe_key=f"sched:{roster.branch_id}:{athlete.athlete_number}:{new_hash}",
                )
                sent += 1 if ok else 0
        elif snap.schedule_hash != new_hash:
            snap.schedule_hash = new_hash
            snap.schedule_json = _schedule_json(athlete)
            await db.commit()
            if not athlete.schedule:
                continue  # schedule removed — don't notify
            account = accounts.get(athlete.athlete_number)
            if account:
                ok = await send_push_to_account(
                    db, account.id, "schedule_change",
                    "Schedule updated",
                    _schedule_body(athlete),
                    data={"screen": "schedule"},
                    dedupe_key=f"sched:{roster.branch_id}:{athlete.athlete_number}:{new_hash}",
                )
                sent += 1 if ok else 0

    if seed_mode:
        logger.info(f"Seeded schedule snapshots for branch {roster.branch_id} (no notifications)")
    return sent


def _current_absence_streak(athlete: Athlete, today: str) -> tuple[int, str]:
    """(streak_length, streak_start_date) of trailing consecutive absences up to today."""
    marks = sorted((d, m) for d, m in athlete.attendance.items() if d <= today)
    streak = 0
    start = ""
    for d, m in reversed(marks):
        if m == "A":
            streak += 1
            start = d
        else:
            break
    return streak, start


async def check_missed_sessions(roster: BranchRoster, db: AsyncSession) -> int:
    """Notify customers whose athlete missed their last 2 recorded sessions."""
    accounts = await _active_accounts(db, roster.branch_id)
    today = date.today().isoformat()

    sent = 0
    for athlete in roster.athletes:
        if not athlete.attendance:
            continue
        streak, streak_start = _current_absence_streak(athlete, today)
        if streak < 2:
            continue
        account = accounts.get(athlete.athlete_number)
        if not account:
            continue
        ok = await send_push_to_account(
            db, account.id, "missed_sessions",
            "We miss you!",
            f"{athlete.name} has missed {streak} sessions. Are you okay?",
            data={"screen": "schedule"},
            dedupe_key=f"missed:{roster.branch_id}:{athlete.athlete_number}:{streak_start}",
        )
        sent += 1 if ok else 0
    return sent


async def send_payment_reminders(db: AsyncSession, rosters: dict[int, BranchRoster]) -> int:
    """Notify customers unpaid for the current period. Deduped once per month."""
    now = datetime.now()
    period = now.strftime("%Y-%m")
    month_label = now.strftime("%B")

    sent = 0
    for branch_id, roster in rosters.items():
        accounts = await _active_accounts(db, branch_id)

        result = await db.execute(
            select(Payment.athlete_number).where(
                Payment.branch_id == branch_id,
                Payment.period == period,
                Payment.status == "paid",
            )
        )
        paid_numbers = {row[0] for row in result.all()}

        for athlete in roster.athletes:
            # A pay value in Excel means the fee was paid (reconciliation records it),
            # so unpaid = no paid Payment row for the current period.
            if athlete.athlete_number in paid_numbers:
                continue
            account = accounts.get(athlete.athlete_number)
            if not account:
                continue
            ok = await send_push_to_account(
                db, account.id, "payment_reminder",
                "Payment reminder",
                f"{athlete.name}'s {month_label} fee is unpaid. "
                f"Please pay before the end of the month or you will lose your spot.",
                data={"screen": "pay"},
                dedupe_key=f"payrem:{branch_id}:{athlete.athlete_number}:{period}",
            )
            sent += 1 if ok else 0
    return sent


async def run_roster_triggers(roster: BranchRoster, db: AsyncSession) -> dict:
    """Run schedule + missed-session checks for one branch, each isolated."""
    counts = {"schedule": 0, "missed": 0}
    try:
        counts["schedule"] = await check_schedule_changes(roster, db)
    except Exception as e:
        logger.error(f"Schedule-change trigger error for branch {roster.branch_id}: {e}")
    try:
        counts["missed"] = await check_missed_sessions(roster, db)
    except Exception as e:
        logger.error(f"Missed-sessions trigger error for branch {roster.branch_id}: {e}")
    return counts
