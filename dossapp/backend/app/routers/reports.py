"""Monthly athlete reports — staff (admin/assistant/coach) write them, athletes read them."""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.admin_user import AdminUser
from app.models.athlete_report import AthleteReport
from app.routers.deps import get_current_customer, get_current_staff, enforce_branch_scope
from app.schemas.report import ReportUpsert, ReportOut, ReportSwimmer, ReportSwimmersResponse
from app.services.coach_accounts import normalize_coach_name
from app.services.push_service import send_push_to_account

logger = logging.getLogger(__name__)

router = APIRouter(tags=["reports"])


def _get_roster_source():
    from app.main import roster_source
    return roster_source


def _current_period() -> str:
    now = datetime.now(timezone.utc)
    return f"{now.year}-{now.month:02d}"


def _staff_display_name(staff: AdminUser) -> str:
    return staff.coach_name or staff.username


async def _get_roster(branch_id: int):
    roster = await _get_roster_source().get_branch_roster(branch_id)
    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")
    return roster


def _athlete_names(roster) -> dict[int, str]:
    return {a.athlete_number: a.name for a in roster.athletes}


# ── Staff side ───────────────────────────────────────────────────────────────

@router.get("/staff/reports/swimmers", response_model=ReportSwimmersResponse)
async def report_swimmers(
    branch_id: int | None = Query(None),
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    """Swimmers the current staff member can write reports for.

    Coaches: only their own swimmers. Assistants: their branch. Admins: any branch (pass branch_id).
    """
    if staff.role == "admin":
        if branch_id is None:
            raise HTTPException(status_code=400, detail="branch_id is required for admins")
        target_branch = branch_id
    else:
        target_branch = staff.assigned_branch_id
        if not target_branch:
            raise HTTPException(status_code=403, detail="No branch assigned")
        if branch_id is not None and branch_id != target_branch:
            raise HTTPException(status_code=403, detail="Access denied to this branch")

    roster = await _get_roster(target_branch)

    if staff.role == "coach":
        if not staff.coach_name:
            raise HTTPException(status_code=403, detail="Coach account has no coach name assigned")
        coach_key = normalize_coach_name(staff.coach_name)
        athletes = [
            a for a in roster.athletes
            if any(slot.coach and normalize_coach_name(slot.coach) == coach_key for slot in a.schedule)
        ]
    else:
        athletes = list(roster.athletes)

    period = _current_period()
    result = await db.execute(
        select(AthleteReport.athlete_number).where(
            AthleteReport.branch_id == target_branch,
            AthleteReport.period == period,
        )
    )
    reported = set(result.scalars().all())

    swimmers = sorted(
        (
            ReportSwimmer(
                athlete_number=a.athlete_number,
                name=a.name,
                has_current_report=a.athlete_number in reported,
            )
            for a in athletes
        ),
        key=lambda s: s.name.lower(),
    )

    return ReportSwimmersResponse(
        branch_id=target_branch,
        branch_name=roster.branch_name,
        current_period=period,
        swimmers=swimmers,
    )


@router.get("/staff/reports", response_model=list[ReportOut])
async def list_reports_for_athlete(
    branch_id: int = Query(...),
    athlete_number: int = Query(...),
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    enforce_branch_scope(staff, branch_id)

    result = await db.execute(
        select(AthleteReport)
        .where(AthleteReport.branch_id == branch_id, AthleteReport.athlete_number == athlete_number)
        .order_by(AthleteReport.period.desc())
    )
    reports = result.scalars().all()

    name = None
    try:
        roster = await _get_roster(branch_id)
        name = _athlete_names(roster).get(athlete_number)
    except HTTPException:
        pass

    out = []
    for r in reports:
        item = ReportOut.model_validate(r)
        item.athlete_name = name
        out.append(item)
    return out


@router.put("/staff/reports", response_model=ReportOut)
async def upsert_report(
    payload: ReportUpsert,
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    enforce_branch_scope(staff, payload.branch_id)

    roster = await _get_roster(payload.branch_id)
    names = _athlete_names(roster)
    if payload.athlete_number not in names:
        raise HTTPException(status_code=404, detail="Athlete not found in branch roster")

    # Coaches may only report on their own swimmers
    if staff.role == "coach":
        coach_key = normalize_coach_name(staff.coach_name or "")
        athlete = next(a for a in roster.athletes if a.athlete_number == payload.athlete_number)
        if not any(slot.coach and normalize_coach_name(slot.coach) == coach_key for slot in athlete.schedule):
            raise HTTPException(status_code=403, detail="This athlete is not in your sessions")

    result = await db.execute(
        select(AthleteReport).where(
            AthleteReport.branch_id == payload.branch_id,
            AthleteReport.athlete_number == payload.athlete_number,
            AthleteReport.period == payload.period,
        )
    )
    report = result.scalar_one_or_none()
    is_new = report is None

    if report is None:
        report = AthleteReport(
            branch_id=payload.branch_id,
            athlete_number=payload.athlete_number,
            period=payload.period,
        )
        db.add(report)

    report.technique = payload.technique
    report.endurance = payload.endurance
    report.commitment = payload.commitment
    report.discipline = payload.discipline
    report.coach_notes = payload.coach_notes
    report.goals = payload.goals
    report.created_by_id = staff.id
    report.created_by_name = _staff_display_name(staff)
    report.created_by_role = staff.role

    await db.commit()
    await db.refresh(report)

    # Notify the athlete (only on first publish for this period)
    if is_new:
        try:
            acc_result = await db.execute(
                select(Account).where(
                    Account.branch_id == payload.branch_id,
                    Account.athlete_number == payload.athlete_number,
                    Account.status == "active",
                )
            )
            account = acc_result.scalars().first()
            if account:
                if account.language == "ar":
                    title = "تقريرك الشهري جاهز"
                    body = f"الكابتن {report.created_by_name} نشر تقرير شهر {payload.period}. افتحه من التطبيق!"
                else:
                    title = "Your monthly report is ready"
                    body = f"Coach {report.created_by_name} published your {payload.period} report. Check it out!"
                await send_push_to_account(
                    db, account.id, "monthly_report", title, body,
                    data={"type": "monthly_report", "period": payload.period},
                    dedupe_key=f"report:{payload.branch_id}:{payload.athlete_number}:{payload.period}",
                )
        except Exception as e:
            logger.error(f"Report push notification error: {e}")

    out = ReportOut.model_validate(report)
    out.athlete_name = names.get(payload.athlete_number)
    return out


@router.delete("/staff/reports/{report_id}")
async def delete_report(
    report_id: int,
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(AthleteReport).where(AthleteReport.id == report_id))
    report = result.scalar_one_or_none()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    enforce_branch_scope(staff, report.branch_id)

    await db.delete(report)
    await db.commit()
    return {"deleted": True}


# ── Athlete side ─────────────────────────────────────────────────────────────

@router.get("/me/reports", response_model=list[ReportOut])
async def my_reports(
    customer: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(AthleteReport)
        .where(
            AthleteReport.branch_id == customer.branch_id,
            AthleteReport.athlete_number == customer.athlete_number,
        )
        .order_by(AthleteReport.period.desc())
    )
    return [ReportOut.model_validate(r) for r in result.scalars().all()]
