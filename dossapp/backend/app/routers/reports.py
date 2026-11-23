"""Monthly athlete reports — staff (admin/assistant/coach) send them, athletes read them.

A report is either an uploaded PDF or a written note (a PDF may carry a note too).
The athlete is notified every time one is sent or updated.
"""

import logging
import re
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.orm import undefer
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


def _ensure_coach_owns(staff: AdminUser, roster, athlete_number: int) -> None:
    """Coaches may only touch reports of swimmers in their own sessions.
    Admins and assistants are limited by branch only."""
    if staff.role != "coach":
        return
    coach_key = normalize_coach_name(staff.coach_name or "")
    athlete = next((a for a in roster.athletes if a.athlete_number == athlete_number), None)
    if athlete is None or not any(
        slot.coach and normalize_coach_name(slot.coach) == coach_key for slot in athlete.schedule
    ):
        raise HTTPException(status_code=403, detail="This athlete is not in your sessions")


def _header_safe(name: str) -> str:
    """A filename that is legal inside a Content-Disposition header."""
    return re.sub(r'[^\x20-\x7e]|["\\]', "_", name) or "report.pdf"


@router.get("/staff/reports", response_model=list[ReportOut])
async def list_reports_for_athlete(
    branch_id: int = Query(...),
    athlete_number: int = Query(...),
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    enforce_branch_scope(staff, branch_id)
    if staff.role == "coach":
        _ensure_coach_owns(staff, await _get_roster(branch_id), athlete_number)

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

    return [_report_out(r, name) for r in reports]


MAX_PDF_BYTES = 10 * 1024 * 1024  # 10 MB


def _report_out(report: AthleteReport, name: str | None = None) -> ReportOut:
    out = ReportOut.model_validate(report)
    out.has_pdf = bool(report.pdf_filename)
    out.athlete_name = name
    return out


async def _save_report(
    db: AsyncSession,
    staff: AdminUser,
    branch_id: int,
    athlete_number: int,
    period: str,
    note: str | None,
    pdf: tuple[str, bytes] | None,
) -> ReportOut:
    """Create or replace the report for one athlete and month, then notify them."""
    enforce_branch_scope(staff, branch_id)

    roster = await _get_roster(branch_id)
    names = _athlete_names(roster)
    if athlete_number not in names:
        raise HTTPException(status_code=404, detail="Athlete not found in branch roster")

    _ensure_coach_owns(staff, roster, athlete_number)

    note = (note or "").strip() or None
    if pdf is None and note is None:
        raise HTTPException(status_code=400, detail="Write a note or upload a PDF")

    result = await db.execute(
        select(AthleteReport).where(
            AthleteReport.branch_id == branch_id,
            AthleteReport.athlete_number == athlete_number,
            AthleteReport.period == period,
        )
    )
    report = result.scalar_one_or_none()

    if report is None:
        report = AthleteReport(
            branch_id=branch_id,
            athlete_number=athlete_number,
            period=period,
            technique=0, endurance=0, commitment=0, discipline=0,
        )
        db.add(report)

    report.coach_notes = note
    report.goals = None
    if pdf is not None:
        report.pdf_filename, report.pdf_data = pdf
    else:
        # A note-only save replaces whatever was sent before for this month
        report.pdf_filename = None
        report.pdf_data = None
    report.created_by_id = staff.id
    report.created_by_name = _staff_display_name(staff)
    report.created_by_role = staff.role

    await db.commit()
    await db.refresh(report)
    out = _report_out(report, names.get(athlete_number))

    # Always notify: the inbox entry carries the note itself, or says a PDF is waiting.
    try:
        acc_result = await db.execute(
            select(Account).where(
                Account.branch_id == branch_id,
                Account.athlete_number == athlete_number,
                Account.status == "active",
            )
        )
        account = acc_result.scalars().first()
        if account:
            sender = out.created_by_name
            if account.language == "ar":
                title = f"تقرير شهر {period}"
                body = note or f"الكابتن {sender} أرسل تقريرك الشهري. افتحه من التطبيق."
            else:
                title = f"Your {period} report"
                body = note or f"Coach {sender} sent your monthly report. Open the app to view it."
            if len(body) > 240:
                body = body[:237].rstrip() + "..."
            await send_push_to_account(
                db, account.id, "monthly_report", title, body,
                data={"type": "monthly_report", "period": period, "report_id": str(out.id)},
            )
    except Exception as e:
        logger.error(f"Report push notification error: {e}")

    return out


@router.put("/staff/reports", response_model=ReportOut)
async def upsert_report(
    payload: ReportUpsert,
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    """Send a note as the month's report."""
    # Older app builds send notes and goals separately; keep both.
    note = "\n\n".join(t.strip() for t in (payload.coach_notes, payload.goals) if t and t.strip())
    return await _save_report(db, staff, payload.branch_id, payload.athlete_number, payload.period, note, None)


@router.post("/staff/reports/pdf", response_model=ReportOut)
async def upload_report_pdf(
    branch_id: int = Form(...),
    athlete_number: int = Form(...),
    period: str = Form(...),
    note: str | None = Form(None),
    file: UploadFile = File(...),
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    """Send a PDF (with an optional note) as the month's report."""
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", period):
        raise HTTPException(status_code=400, detail="period must be YYYY-MM")
    if note and len(note) > 4000:
        raise HTTPException(status_code=400, detail="Note is too long")

    data = await file.read(MAX_PDF_BYTES + 1)
    if len(data) > MAX_PDF_BYTES:
        raise HTTPException(status_code=413, detail="PDF is larger than 10 MB")
    if not data.startswith(b"%PDF-"):
        raise HTTPException(status_code=400, detail="That file is not a PDF")

    filename = re.sub(r"[^\w.\- ]", "_", (file.filename or "report.pdf").rsplit("/", 1)[-1])[:200] or "report.pdf"
    if not filename.lower().endswith(".pdf"):
        filename += ".pdf"

    return await _save_report(db, staff, branch_id, athlete_number, period, note, (filename, data))


def _pdf_response(report: AthleteReport | None) -> Response:
    if report is None or not report.pdf_data:
        raise HTTPException(status_code=404, detail="This report has no PDF")
    return Response(
        content=bytes(report.pdf_data),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{_header_safe(report.pdf_filename or "report.pdf")}"'},
    )


@router.get("/staff/reports/{report_id}/pdf")
async def staff_report_pdf(
    report_id: int,
    staff: AdminUser = Depends(get_current_staff),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(AthleteReport).options(undefer(AthleteReport.pdf_data)).where(AthleteReport.id == report_id)
    )
    report = result.scalar_one_or_none()
    if report is None:
        raise HTTPException(status_code=404, detail="Report not found")
    enforce_branch_scope(staff, report.branch_id)
    if staff.role == "coach":
        _ensure_coach_owns(staff, await _get_roster(report.branch_id), report.athlete_number)
    return _pdf_response(report)


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
    if staff.role == "coach":
        _ensure_coach_owns(staff, await _get_roster(report.branch_id), report.athlete_number)

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
    return [_report_out(r) for r in result.scalars().all()]


@router.get("/me/reports/{report_id}/pdf")
async def my_report_pdf(
    report_id: int,
    customer: Account = Depends(get_current_customer),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(AthleteReport).options(undefer(AthleteReport.pdf_data)).where(
            AthleteReport.id == report_id,
            AthleteReport.branch_id == customer.branch_id,
            AthleteReport.athlete_number == customer.athlete_number,
        )
    )
    return _pdf_response(result.scalar_one_or_none())
