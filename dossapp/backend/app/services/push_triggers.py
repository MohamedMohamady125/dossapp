"""Notification triggers driven by parsed roster data.

1. Schedule entered/changed — per-athlete schedule hash vs stored snapshot.
2. Missed 2 sessions (paid) — friendly check-in notification.
3. Payment reminder — every 2 days from 25th until paid.
4. Spot lost — unpaid by 2nd of month → suspended.

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


# ── Bilingual message helpers ──

MONTHS_AR = {
    1: "يناير", 2: "فبراير", 3: "مارس", 4: "أبريل",
    5: "مايو", 6: "يونيو", 7: "يوليو", 8: "أغسطس",
    9: "سبتمبر", 10: "أكتوبر", 11: "نوفمبر", 12: "ديسمبر",
}


def _t(lang: str, en: str, ar: str) -> str:
    return ar if lang == "ar" else en


def _schedule_hash(athlete: Athlete) -> str:
    parts = sorted((s.coach or "", s.time_block or "", s.day_pair or "") for s in athlete.schedule)
    return hashlib.sha256(repr(parts).encode()).hexdigest()


def _schedule_json(athlete: Athlete) -> list[dict]:
    return [
        {"coach": s.coach, "time_block": s.time_block, "day_pair": s.day_pair}
        for s in athlete.schedule
    ]


def _schedule_body(athlete: Athlete, lang: str) -> str:
    lines = []
    for s in athlete.schedule:
        part = s.day_pair or ("أيام غير محددة" if lang == "ar" else "Days TBD")
        if s.time_block:
            part += f" {s.time_block}"
        if s.coach:
            coach_label = "مع كابتن" if lang == "ar" else "with Coach"
            part += f" {coach_label} {s.coach}"
        lines.append(part)
    if lines:
        prefix = f"جدول {athlete.name}: " if lang == "ar" else f"{athlete.name}'s schedule: "
        body = prefix + "؛ ".join(lines) if lang == "ar" else prefix + "; ".join(lines)
    else:
        body = (
            f"تم تحديث جدول {athlete.name}."
            if lang == "ar"
            else f"{athlete.name}'s schedule was updated."
        )
    return body[:1000]


async def _all_accounts(db: AsyncSession, branch_id: int) -> dict[int, Account]:
    """All accounts (active + suspended) for notification eligibility."""
    result = await db.execute(
        select(Account).where(
            Account.branch_id == branch_id,
            Account.status.in_(["active", "suspended"]),
        )
    )
    return {a.athlete_number: a for a in result.scalars().all()}


async def _active_accounts(db: AsyncSession, branch_id: int) -> dict[int, Account]:
    result = await db.execute(
        select(Account).where(Account.branch_id == branch_id, Account.status == "active")
    )
    return {a.athlete_number: a for a in result.scalars().all()}


# ── 1. Schedule changes ──

async def check_schedule_changes(roster: BranchRoster, db: AsyncSession) -> int:
    """Notify customers whose athlete's schedule appeared or changed."""
    accounts = await _active_accounts(db, roster.branch_id)

    result = await db.execute(
        select(ScheduleSnapshot).where(ScheduleSnapshot.branch_id == roster.branch_id)
    )
    snapshots = {s.athlete_number: s for s in result.scalars().all()}

    seed_mode = len(snapshots) == 0
    sent = 0
    needs_notify = []

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
            if not seed_mode:
                needs_notify.append((athlete, new_hash, True))  # is_new=True
        elif snap.schedule_hash != new_hash:
            snap.schedule_hash = new_hash
            snap.schedule_json = _schedule_json(athlete)
            if athlete.schedule:
                needs_notify.append((athlete, new_hash, False))  # is_new=False

    await db.commit()

    if seed_mode:
        logger.info(f"Seeded schedule snapshots for branch {roster.branch_id} (no notifications)")
        return 0

    for athlete, new_hash, is_new in needs_notify:
        account = accounts.get(athlete.athlete_number)
        if account:
            lang = account.language or "en"
            title = _t(lang,
                       "Schedule added" if is_new else "Schedule updated",
                       "تم إضافة الجدول" if is_new else "تم تحديث الجدول")
            ok = await send_push_to_account(
                db, account.id, "schedule_change",
                title,
                _schedule_body(athlete, lang),
                data={"screen": "schedule"},
                dedupe_key=f"sched:{roster.branch_id}:{athlete.athlete_number}:{new_hash}",
            )
            sent += 1 if ok else 0

    return sent


# ── 2. Missed sessions check-in (paid athletes) ──

def _current_absence_streak(athlete: Athlete, today: str) -> tuple[int, str]:
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
    """Notify paid athletes who missed 2+ consecutive sessions with a check-in."""
    accounts = await _active_accounts(db, roster.branch_id)
    today = date.today().isoformat()
    period = date.today().strftime("%Y-%m")

    result = await db.execute(
        select(Payment.athlete_number).where(
            Payment.branch_id == roster.branch_id,
            Payment.period == period,
            Payment.status == "paid",
        )
    )
    paid_numbers = {row[0] for row in result.all()}

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

        # Only send check-in to PAID athletes (unpaid get payment reminders / spot-lost instead)
        is_paid = athlete.athlete_number in paid_numbers or bool(athlete.pay)
        if not is_paid:
            continue

        lang = account.language or "en"
        title = _t(lang, "We miss you! 🏊", "اشتقنالك! 🏊")
        body = _t(
            lang,
            f"Hi! {athlete.name} has missed {streak} consecutive sessions. "
            f"We hope everything is okay — your spot is reserved and your coach "
            f"is looking forward to seeing you back in the pool!",
            f"أهلاً! {athlete.name} غاب عن {streak} حصص متتالية. "
            f"نتمنى إن كل حاجة تمام — مكانك محجوز ومدربك مستنيك ترجع!",
        )

        ok = await send_push_to_account(
            db, account.id, "missed_sessions",
            title, body,
            data={"screen": "home"},
            dedupe_key=f"missed:{roster.branch_id}:{athlete.athlete_number}:{streak_start}",
        )
        sent += 1 if ok else 0
    return sent


# ── 3. Payment reminders (25th, every 2 days until paid) ──

async def send_payment_reminders(db: AsyncSession, rosters: dict[int, BranchRoster]) -> int:
    """Send payment reminders to unpaid athletes. Deduped per day so safe to re-run."""
    now = datetime.now()
    period = now.strftime("%Y-%m")
    month_num = now.month
    day = now.day
    month_en = now.strftime("%B")
    month_ar = MONTHS_AR.get(month_num, month_en)
    # Dedupe key includes the day so the same user can get reminders on different days
    day_key = now.strftime("%Y-%m-%d")

    sent = 0
    for branch_id, roster in rosters.items():
        accounts = await _all_accounts(db, branch_id)

        result = await db.execute(
            select(Payment.athlete_number).where(
                Payment.branch_id == branch_id,
                Payment.period == period,
                Payment.status == "paid",
            )
        )
        paid_numbers = {row[0] for row in result.all()}

        for athlete in roster.athletes:
            if athlete.athlete_number in paid_numbers:
                continue
            # Also skip if Excel Pay column shows paid
            if athlete.pay:
                try:
                    if float(athlete.pay) > 0:
                        continue
                except (ValueError, TypeError):
                    pass
            account = accounts.get(athlete.athlete_number)
            if not account:
                continue

            lang = account.language or "en"
            title = _t(lang, "Payment Reminder 💳", "تذكير بالدفع 💳")

            if day <= 1:
                # Urgent: last day before spot is lost
                body = _t(
                    lang,
                    f"⚠️ {athlete.name}'s {month_en} fee is still unpaid. "
                    f"Pay today to keep your spot — tomorrow your enrollment will be suspended.",
                    f"⚠️ اشتراك {athlete.name} لشهر {month_ar} لم يتم دفعه بعد. "
                    f"ادفع النهاردة عشان تحافظ على مكانك — بكرة هيتم إيقاف تسجيلك.",
                )
            else:
                body = _t(
                    lang,
                    f"{athlete.name}'s {month_en} fee is unpaid. "
                    f"Please pay before the end of the month to keep your spot in the class.",
                    f"اشتراك {athlete.name} لشهر {month_ar} لم يتم دفعه. "
                    f"يرجى الدفع قبل نهاية الشهر للحفاظ على مكانك في الحصة.",
                )

            ok = await send_push_to_account(
                db, account.id, "payment_reminder",
                title, body,
                data={"screen": "pay"},
                dedupe_key=f"payrem:{branch_id}:{athlete.athlete_number}:{day_key}",
            )
            sent += 1 if ok else 0
    return sent


# ── 4. Spot lost (2nd of month — unpaid → suspended) ──

async def send_spot_lost_notifications(db: AsyncSession, rosters: dict[int, BranchRoster]) -> int:
    """On the 2nd: suspend unpaid athletes and notify them they lost their spot."""
    now = datetime.now()
    period = now.strftime("%Y-%m")
    month_num = now.month
    month_en = now.strftime("%B")
    month_ar = MONTHS_AR.get(month_num, month_en)

    sent = 0
    for branch_id, roster in rosters.items():
        accounts = await _all_accounts(db, branch_id)

        result = await db.execute(
            select(Payment.athlete_number).where(
                Payment.branch_id == branch_id,
                Payment.period == period,
                Payment.status == "paid",
            )
        )
        paid_numbers = {row[0] for row in result.all()}

        for athlete in roster.athletes:
            if athlete.athlete_number in paid_numbers:
                continue
            if athlete.pay:
                try:
                    if float(athlete.pay) > 0:
                        continue
                except (ValueError, TypeError):
                    pass
            account = accounts.get(athlete.athlete_number)
            if not account or account.status == "suspended":
                continue  # Already suspended or no account

            # Suspend the account
            account.status = "suspended"
            db.add(account)
            await db.flush()

            lang = account.language or "en"
            title = _t(lang, "You Lost Your Spot 😔", "فقدت مكانك 😔")
            body = _t(
                lang,
                f"{athlete.name} has lost their spot in the class because {month_en}'s fee was not paid. "
                f"Open the app to request reinstatement and get back to training.",
                f"{athlete.name} فقد مكانه في الحصة لأن اشتراك شهر {month_ar} لم يتم دفعه. "
                f"افتح التطبيق لطلب إعادة التسجيل والعودة للتمرين.",
            )

            ok = await send_push_to_account(
                db, account.id, "spot_lost",
                title, body,
                data={"screen": "suspended"},
                dedupe_key=f"spotlost:{branch_id}:{athlete.athlete_number}:{period}",
            )
            sent += 1 if ok else 0
            logger.info(f"Suspended athlete {athlete.athlete_number} (unpaid for {period})")

    await db.commit()
    return sent


# ── Convenience runners ──

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
