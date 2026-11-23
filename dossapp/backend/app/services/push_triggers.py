"""Notification triggers driven by parsed roster data.

1. Schedule entered/changed — per-athlete schedule hash vs stored snapshot.
2. Missed 2 sessions (paid) — friendly check-in notification.
3. Payment reminder — every 2 days from 25th until paid.
4. Spot lost — unpaid by 2nd of month → suspended.

All triggers are idempotent: send_push_to_account dedupes via NotificationDedupe,
so it's safe to run them repeatedly (serverless lazy loads, crons, dev loop).
"""

import hashlib
import json
import logging
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.payment import Payment
from app.models.push import ScheduleSnapshot
from app.services.push_service import send_push_to_account
from app.services.roster_source import Athlete, BranchRoster

logger = logging.getLogger(__name__)


def local_now() -> datetime:
    """Now in Egypt. The server clock is UTC, and "the 25th" has to mean the
    25th for the parents, not for the server."""
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("Africa/Cairo"))
    except Exception:
        return datetime.now(timezone(timedelta(hours=2)))


def _is_enrolled(athlete: Athlete) -> bool:
    """In a class this month. The roster also lists past swimmers with no
    class; they owe nothing and must not be reminded or suspended."""
    return bool(athlete.type or athlete.days or athlete.schedule)


def _billing_period(roster: BranchRoster, now: datetime) -> str:
    """The month the sheet is billing, which is what the parent sees in the app."""
    return roster.period or now.strftime("%Y-%m")


def _month_names(period: str) -> tuple[str, str]:
    try:
        month = int(period.split("-")[1])
        return date(2000, month, 1).strftime("%B"), MONTHS_AR.get(month, period)
    except (IndexError, ValueError):
        return period, period


# ── Bilingual message helpers ──

MONTHS_AR = {
    1: "يناير", 2: "فبراير", 3: "مارس", 4: "أبريل",
    5: "مايو", 6: "يونيو", 7: "يوليو", 8: "أغسطس",
    9: "سبتمبر", 10: "أكتوبر", 11: "نوفمبر", 12: "ديسمبر",
}


def _t(lang: str, en: str, ar: str) -> str:
    return ar if lang == "ar" else en


# What a parent is told about when it changes. Level, class type, days and
# sessions come from the swimmer's roster row; the slots (days, time, coach)
# come from the class tabs.
_DETAIL_LABELS = {
    "step": ("Level", "المستوى"),
    "type": ("Class type", "نوع التمرين"),
    "days": ("Days", "الأيام"),
    "sessions": ("Sessions", "عدد الحصص"),
}


def _clean_text(value) -> str:
    return " ".join(str(value).split()) if value is not None else ""


def _same(a, b) -> bool:
    """Spacing and letter case are not a change worth a notification."""
    return _clean_text(a).casefold() == _clean_text(b).casefold()


def _class_details(athlete: Athlete) -> dict:
    slots = sorted(
        [_clean_text(s.day_pair), _clean_text(s.time_block), _clean_text(s.coach)]
        for s in athlete.schedule
    )
    details = {field: _clean_text(getattr(athlete, field)) for field in _DETAIL_LABELS}
    details.update({"v": 2, "slots": slots})
    return details


def _details_hash(details: dict) -> str:
    comparable = {
        k: ([[c.casefold() for c in slot] for slot in v] if k == "slots" else str(v).casefold())
        for k, v in details.items()
    }
    return hashlib.sha256(json.dumps(comparable, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def _slots_text(slots: list, lang: str) -> str:
    parts = []
    for day_pair, time_block, coach in slots:
        part = day_pair or _t(lang, "Days not set yet", "الأيام لسه ما اتحددتش")
        if time_block:
            part += f" {time_block}"
        if coach:
            part += f" {_t(lang, 'with Coach', 'مع كابتن')} {coach}"
        parts.append(part)
    return _t(lang, "; ", "؛ ").join(parts)


def _changes_body(name: str, old: dict, new: dict, lang: str) -> str:
    """One short line per thing that changed, newest value first."""
    lines = []
    slots_changed = old.get("slots", []) != new.get("slots", []) and _details_hash(
        {"slots": old.get("slots", [])}) != _details_hash({"slots": new.get("slots", [])})
    for field, (en, ar) in _DETAIL_LABELS.items():
        before, after = old.get(field, ""), new.get(field, "")
        if _same(before, after):
            continue
        # The class tabs already say the days, in more detail
        if field == "days" and slots_changed and new.get("slots"):
            continue
        label = _t(lang, en, ar)
        if after and before:
            lines.append(_t(lang, f"{label} is now {after} (was {before})", f"{label} بقى {after} (كان {before})"))
        elif after:
            lines.append(_t(lang, f"{label} is now {after}", f"{label} بقى {after}"))
        else:
            lines.append(_t(lang, f"{label} was removed", f"{label} اتشال"))
    if slots_changed:
        if new.get("slots"):
            lines.append(_t(lang, "Times: ", "المواعيد: ") + _slots_text(new["slots"], lang))
        else:
            lines.append(_t(lang, "Class times were removed", "مواعيد التمرين اتشالت"))
    if not lines:
        return _t(lang, f"{name}'s class details changed.", f"بيانات تمرين {name} اتغيّرت.")
    return (f"{name}: " + _t(lang, ". ", "، ").join(lines))[:1000]


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


# ── 1. Class changes (level, type, days, sessions, time, coach) ──

async def check_schedule_changes(roster: BranchRoster, db: AsyncSession) -> int:
    """Notify the parent when anything about their swimmer's class changes."""
    accounts = await _active_accounts(db, roster.branch_id)

    result = await db.execute(
        select(ScheduleSnapshot).where(ScheduleSnapshot.branch_id == roster.branch_id)
    )
    snapshots = {s.athlete_number: s for s in result.scalars().all()}

    # First run for this branch, or first run since snapshots started holding
    # level/type/days/sessions: record what is there now and stay silent, so a
    # deploy never pushes "updated" to every parent.
    seed_mode = not any(isinstance(s.schedule_json, dict) for s in snapshots.values())
    needs_notify = []

    for athlete in roster.athletes:
        enrolled = _is_enrolled(athlete)
        details = _class_details(athlete)
        new_hash = _details_hash(details)
        snap = snapshots.get(athlete.athlete_number)

        if snap is None:
            if not enrolled:
                continue
            db.add(ScheduleSnapshot(
                branch_id=roster.branch_id,
                athlete_number=athlete.athlete_number,
                schedule_hash=new_hash,
                schedule_json=details,
            ))
            if not seed_mode:
                needs_notify.append((athlete, {}, details, "", new_hash))
        elif not isinstance(snap.schedule_json, dict):
            snap.schedule_hash = new_hash
            snap.schedule_json = details
        elif snap.schedule_hash != new_hash:
            old_details, old_hash = snap.schedule_json, snap.schedule_hash
            snap.schedule_hash = new_hash
            snap.schedule_json = details
            # Leaving a class is not announced: the sheet is cleared at every
            # month change and that would message every family.
            if enrolled and not seed_mode:
                needs_notify.append((athlete, old_details, details, old_hash, new_hash))

    await db.commit()

    if seed_mode:
        logger.info(f"Seeded class snapshots for branch {roster.branch_id} (no notifications)")
        return 0

    sent = 0
    today = local_now().strftime("%Y%m%d")
    for athlete, old_details, details, old_hash, new_hash in needs_notify:
        account = accounts.get(athlete.athlete_number)
        if not account:
            continue
        lang = account.language or "en"
        is_new = not any(old_details.get(f) for f in (*_DETAIL_LABELS, "slots"))
        title = _t(lang,
                   "Class added" if is_new else "Class changed",
                   "التمرين اتضاف" if is_new else "في تغيير في التمرين")
        ok = await send_push_to_account(
            db, account.id, "schedule_change",
            title,
            _changes_body(athlete.name, old_details, details, lang),
            data={"screen": "schedule"},
            # Old and new together, per day: going back to an earlier class
            # later is a real change and must not be swallowed as a repeat.
            dedupe_key=f"sched:{roster.branch_id}:{athlete.athlete_number}:{old_hash[:16]}:{new_hash[:16]}:{today}",
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
        title = _t(lang, "We miss you", "وحشتنا")
        body = _t(
            lang,
            f"{athlete.name} missed the last {streak} sessions. "
            f"We hope all is well. The spot is still yours and the coach "
            f"is waiting to see you back in the pool.",
            f"{athlete.name} غاب آخر {streak} حصص. "
            f"يا رب تكونوا بخير. المكان لسه محجوز، والكابتن مستنيكم ترجعوا.",
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
    now = local_now()
    day = now.day
    # Dedupe key includes the day so the same user can get reminders on different days
    day_key = now.strftime("%Y-%m-%d")

    sent = 0
    for branch_id, roster in rosters.items():
        period = _billing_period(roster, now)
        month_en, month_ar = _month_names(period)
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
            if athlete.athlete_number in paid_numbers or not _is_enrolled(athlete):
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
            title = _t(lang, "Time to pay", "ميعاد الدفع")

            if day <= 1:
                # Urgent: last day before spot is lost
                body = _t(
                    lang,
                    f"Last day: {athlete.name}'s {month_en} fee is not paid yet. "
                    f"Pay today to keep the spot. Tomorrow the spot goes on hold.",
                    f"آخر يوم: اشتراك {athlete.name} لشهر {month_ar} لسه ما اتدفعش. "
                    f"ادفع النهارده عشان تحافظ على المكان. من بكرة المكان هيتوقف.",
                )
            else:
                body = _t(
                    lang,
                    f"{athlete.name}'s {month_en} fee is not paid yet. "
                    f"Please pay before the month ends to keep the spot in the class.",
                    f"اشتراك {athlete.name} لشهر {month_ar} لسه ما اتدفعش. "
                    f"ادفع قبل آخر الشهر عشان تحافظ على مكانه في التمرين.",
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
    from app.models.reinstatement_request import ReinstatementRequest

    now = local_now()
    calendar_period = now.strftime("%Y-%m")
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    sent = 0
    for branch_id, roster in rosters.items():
        period = _billing_period(roster, now)
        if period != calendar_period:
            # The sheet has not been moved to this month yet, so nobody can
            # have paid for it. Suspending now would suspend the whole branch.
            logger.warning(
                f"Spot-lost skipped for branch {branch_id}: sheet is on {period}, today is {calendar_period}"
            )
            continue
        month_en, month_ar = _month_names(period)
        accounts = await _all_accounts(db, branch_id)

        # Staff already gave these swimmers their spot back this month
        result = await db.execute(
            select(ReinstatementRequest.account_id).where(
                ReinstatementRequest.branch_id == branch_id,
                ReinstatementRequest.status == "approved",
                ReinstatementRequest.reviewed_at >= month_start,
            )
        )
        reinstated = {row[0] for row in result.all()}

        result = await db.execute(
            select(Payment.athlete_number).where(
                Payment.branch_id == branch_id,
                Payment.period == period,
                Payment.status == "paid",
            )
        )
        paid_numbers = {row[0] for row in result.all()}

        for athlete in roster.athletes:
            if athlete.athlete_number in paid_numbers or not _is_enrolled(athlete):
                continue
            if athlete.pay:
                try:
                    if float(athlete.pay) > 0:
                        continue
                except (ValueError, TypeError):
                    pass
            account = accounts.get(athlete.athlete_number)
            if not account or account.status != "active" or account.id in reinstated:
                continue  # No account, already suspended/closed, or reinstated by staff

            # Suspend the account
            account.status = "suspended"
            db.add(account)
            await db.flush()

            lang = account.language or "en"
            title = _t(lang, "Your spot is on hold", "مكانك اتوقف")
            body = _t(
                lang,
                f"{athlete.name}'s spot in the class is on hold because the {month_en} fee was not paid. "
                f"Open the app to ask for the spot back.",
                f"مكان {athlete.name} في التمرين اتوقف عشان اشتراك شهر {month_ar} ما اتدفعش. "
                f"افتح التطبيق واطلب المكان تاني.",
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
