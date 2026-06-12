"""Admin/Assistant endpoints — branches, athletes, provisioning, payments, analytics, health."""

import re
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.account import Account
from app.models.admin_user import AdminUser
from app.models.payment import Payment
from app.models.receipt import Receipt
from app.routers.deps import get_current_admin, enforce_branch_scope
from app.schemas.athlete import AthleteDetail, ProvisionRequest, ProvisionResponse, ScheduleSlot
from app.schemas.payment import PaymentOut, ReceiptOut
from app.services.notifications import enqueue_notification
from app.utils.auth import generate_login_code, generate_temp_password, hash_password
from app.utils.phone import normalize_phone

# Discount patterns to flag in comments
_DISCOUNT_PATTERNS = re.compile(
    r"(\d+%|discount|خصم|ترحيل|D$|Dec$)", re.IGNORECASE
)

router = APIRouter(tags=["admin"])


def _get_roster_source():
    from app.main import roster_source
    return roster_source


@router.get("/branches")
async def list_branches(admin: AdminUser = Depends(get_current_admin)):
    source = _get_roster_source()
    rosters = await source.get_all_rosters()

    branches = []
    for bid, roster in rosters.items():
        if admin.role == "assistant" and admin.assigned_branch_id != bid:
            continue
        branches.append({
            "id": bid,
            "name": roster.branch_name,
            "athlete_count": len(roster.athletes),
        })
    return branches


@router.get("/branches/{branch_id}/athletes", response_model=list[AthleteDetail])
async def list_athletes(
    branch_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    enforce_branch_scope(admin, branch_id)
    source = _get_roster_source()
    roster = await source.get_branch_roster(branch_id)
    if not roster:
        raise HTTPException(status_code=404, detail="Branch not found")

    # Get existing accounts for this branch
    result = await db.execute(
        select(Account.athlete_number).where(Account.branch_id == branch_id)
    )
    provisioned = {row[0] for row in result.all()}

    return [
        AthleteDetail(
            branch=roster.branch_name,
            branch_id=branch_id,
            athlete_number=a.athlete_number,
            name=a.name,
            age=a.age_computed,
            date_of_birth=a.date_of_birth,
            gender=a.gender,
            level=a.step,
            type=a.type,
            days=a.days,
            sessions=a.sessions,
            segment=a.segment,
            pay=a.pay,
            phone1=a.phone1,
            phone2=a.phone2,
            comment=a.comment,
            receipt_no=a.receipt_no,
            has_account=a.athlete_number in provisioned,
            schedule=[
                ScheduleSlot(coach=s.coach, time_block=s.time_block, day_pair=s.day_pair)
                for s in a.schedule
            ],
        )
        for a in roster.athletes
    ]


@router.get("/branches/{branch_id}/athletes/{athlete_number}", response_model=AthleteDetail)
async def get_athlete_detail(
    branch_id: int,
    athlete_number: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    enforce_branch_scope(admin, branch_id)
    source = _get_roster_source()
    roster = await source.get_branch_roster(branch_id)
    if not roster:
        raise HTTPException(status_code=404, detail="Branch not found")

    athlete = next((a for a in roster.athletes if a.athlete_number == athlete_number), None)
    if not athlete:
        raise HTTPException(status_code=404, detail="Athlete not found")

    result = await db.execute(
        select(Account).where(Account.branch_id == branch_id, Account.athlete_number == athlete_number)
    )
    has_account = result.scalar_one_or_none() is not None

    return AthleteDetail(
        branch=roster.branch_name,
        branch_id=branch_id,
        athlete_number=athlete.athlete_number,
        name=athlete.name,
        age=athlete.age_computed,
        date_of_birth=athlete.date_of_birth,
        gender=athlete.gender,
        level=athlete.step,
        type=athlete.type,
        days=athlete.days,
        sessions=athlete.sessions,
        segment=athlete.segment,
        pay=athlete.pay,
        phone1=athlete.phone1,
        phone2=athlete.phone2,
        comment=athlete.comment,
        receipt_no=athlete.receipt_no,
        has_account=has_account,
        schedule=[
            ScheduleSlot(coach=s.coach, time_block=s.time_block, day_pair=s.day_pair)
            for s in athlete.schedule
        ],
    )


@router.post("/branches/{branch_id}/athletes/{athlete_number}/provision", response_model=ProvisionResponse)
async def provision_account(
    branch_id: int,
    athlete_number: int,
    req: ProvisionRequest,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    enforce_branch_scope(admin, branch_id)
    source = _get_roster_source()
    roster = await source.get_branch_roster(branch_id)
    if not roster:
        raise HTTPException(status_code=404, detail="Branch not found")

    athlete = next((a for a in roster.athletes if a.athlete_number == athlete_number), None)
    if not athlete:
        raise HTTPException(status_code=404, detail="Athlete not found in roster")

    # Check if already provisioned
    result = await db.execute(
        select(Account).where(Account.branch_id == branch_id, Account.athlete_number == athlete_number)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Account already exists for this athlete")

    login_code = generate_login_code(roster.branch_name, athlete_number)
    temp_password = generate_temp_password()

    account = Account(
        branch_id=branch_id,
        athlete_number=athlete_number,
        login_code=login_code,
        password_hash=hash_password(temp_password),
        must_change_password=True,
        name_at_creation=athlete.name,
        dob_at_creation=athlete.date_of_birth,
        phone_at_creation=athlete.phone1,
        created_by_admin_id=admin.id,
    )
    db.add(account)
    await db.flush()

    sent_to = None
    if req.delivery_method in ("auto_send", "both"):
        phone = normalize_phone(athlete.phone1)
        if phone:
            msg = (
                f"Aqua Athletic Academy\n"
                f"Your login credentials:\n"
                f"Code: {login_code}\n"
                f"Password: {temp_password}\n"
                f"Please change your password on first login."
            )
            await enqueue_notification("sms", phone, msg, account_id=account.id)
            await enqueue_notification("whatsapp", phone, msg, account_id=account.id)
            sent_to = phone

    return ProvisionResponse(
        login_code=login_code,
        temp_password=temp_password,
        delivery_method=req.delivery_method,
        sent_to=sent_to,
    )


@router.post("/branches/{branch_id}/athletes/{athlete_number}/reprovision", response_model=ProvisionResponse)
async def reprovision_account(
    branch_id: int,
    athlete_number: int,
    req: ProvisionRequest,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Reset an existing account's password and return new credentials."""
    enforce_branch_scope(admin, branch_id)

    result = await db.execute(
        select(Account).where(Account.branch_id == branch_id, Account.athlete_number == athlete_number)
    )
    account = result.scalar_one_or_none()
    if not account:
        raise HTTPException(status_code=404, detail="No account exists for this athlete")

    temp_password = generate_temp_password()
    account.password_hash = hash_password(temp_password)
    account.must_change_password = True
    db.add(account)

    sent_to = None
    if req.delivery_method in ("auto_send", "both"):
        source = _get_roster_source()
        roster = await source.get_branch_roster(branch_id)
        athlete = next((a for a in roster.athletes if a.athlete_number == athlete_number), None) if roster else None
        phone = normalize_phone(athlete.phone1) if athlete else None
        if phone:
            msg = (
                f"Aqua Athletic Academy\n"
                f"Your updated login credentials:\n"
                f"Code: {account.login_code}\n"
                f"Password: {temp_password}\n"
                f"Please change your password on first login."
            )
            await enqueue_notification("sms", phone, msg, account_id=account.id)
            await enqueue_notification("whatsapp", phone, msg, account_id=account.id)
            sent_to = phone

    return ProvisionResponse(
        login_code=account.login_code,
        temp_password=temp_password,
        delivery_method=req.delivery_method,
        sent_to=sent_to,
    )


@router.post("/branches/{branch_id}/athletes/{athlete_number}/mark-paid")
async def mark_athlete_paid(
    branch_id: int,
    athlete_number: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin manually marks an athlete as paid for the current period."""
    enforce_branch_scope(admin, branch_id)
    source = _get_roster_source()
    roster = await source.get_branch_roster(branch_id)
    if not roster:
        raise HTTPException(status_code=404, detail="Branch not found")

    athlete = next((a for a in roster.athletes if a.athlete_number == athlete_number), None)
    if not athlete:
        raise HTTPException(status_code=404, detail="Athlete not found in roster")

    if not athlete.pay:
        raise HTTPException(status_code=400, detail="No bill amount set for this athlete")

    period = datetime.now().strftime("%Y-%m")

    from app.services.payment_service import record_manual_payment
    receipt = await record_manual_payment(
        db=db,
        branch_id=branch_id,
        athlete_number=athlete_number,
        period=period,
        amount_paid=Decimal(athlete.pay),
        amount_owed=Decimal(athlete.pay),
        athlete_name=athlete.name,
        branch_name=roster.branch_name,
        level=athlete.step,
        athlete_type=athlete.type,
        phone=athlete.phone1,
    )

    if not receipt:
        raise HTTPException(status_code=400, detail="Already paid for this period")

    return {"message": "Marked as paid", "receipt_number": receipt.receipt_number}


@router.get("/branches/{branch_id}/payments", response_model=list[PaymentOut])
async def list_payments(
    branch_id: int,
    period: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    enforce_branch_scope(admin, branch_id)

    query = select(Payment).where(Payment.branch_id == branch_id)
    if period:
        query = query.where(Payment.period == period)
    if status:
        query = query.where(Payment.status == status)
    query = query.order_by(Payment.created_at.desc())

    result = await db.execute(query)
    payments = result.scalars().all()

    # Look up athlete names from roster cache
    source = _get_roster_source()
    roster = await source.get_branch_roster(branch_id)
    athlete_map = {a.athlete_number: a for a in roster.athletes} if roster else {}

    return [
        PaymentOut(
            id=p.id,
            branch_id=p.branch_id,
            athlete_number=p.athlete_number,
            athlete_name=athlete_map[p.athlete_number].name if p.athlete_number in athlete_map else f"Athlete #{p.athlete_number}",
            level=athlete_map[p.athlete_number].step if p.athlete_number in athlete_map else None,
            athlete_type=athlete_map[p.athlete_number].type if p.athlete_number in athlete_map else None,
            period=p.period,
            source=p.source,
            amount_paid=str(p.amount_paid),
            status=p.status,
            paid_at=p.paid_at,
        )
        for p in payments
    ]


@router.post("/admin/receipts/{receipt_id}/resend")
async def admin_resend_receipt(
    receipt_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Receipt).where(Receipt.id == receipt_id))
    receipt = result.scalar_one_or_none()
    if not receipt:
        raise HTTPException(status_code=404, detail="Receipt not found")

    # Scope check
    payment_result = await db.execute(select(Payment).where(Payment.id == receipt.payment_id))
    payment = payment_result.scalar_one_or_none()
    if payment:
        enforce_branch_scope(admin, payment.branch_id)

    if receipt.phone:
        body = f"Receipt {receipt.receipt_number}: {receipt.amount_paid} EGP PAID"
        await enqueue_notification("sms", receipt.phone, body, receipt_id=receipt.id)
        await enqueue_notification("whatsapp", receipt.phone, body, attachment=receipt.pdf_data, receipt_id=receipt.id)

    return {"message": "Receipt resend queued"}


@router.get("/admin/analytics")
async def get_analytics(
    scope: str = Query("branch"),
    branch_id: Optional[int] = Query(None),
    period: Optional[str] = Query(None),
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    source = _get_roster_source()

    if scope == "branch" and branch_id:
        enforce_branch_scope(admin, branch_id)
        roster = await source.get_branch_roster(branch_id)
        if not roster:
            raise HTTPException(status_code=404, detail="Branch not found")
        rosters = {branch_id: roster}
    else:
        rosters = await source.get_all_rosters()
        if admin.role == "assistant":
            rosters = {k: v for k, v in rosters.items() if k == admin.assigned_branch_id}

    if not period:
        period = datetime.now().strftime("%Y-%m")

    # Tier 1 analytics
    analytics = {"period": period, "branches": {}}

    for bid, roster in rosters.items():
        athletes = roster.athletes

        # ── Basic counts ──
        level_counts: dict[str, int] = {}
        type_counts: dict[str, int] = {}
        segment_counts: dict[str, int] = {}
        gender_counts: dict[str, int] = {}
        day_counts: dict[str, int] = {}
        session_counts: dict[str, int] = {}

        for a in athletes:
            level_counts[a.step or "No Level"] = level_counts.get(a.step or "No Level", 0) + 1
            type_counts[a.type or "No Type"] = type_counts.get(a.type or "No Type", 0) + 1
            segment_counts[a.segment or "No Segment"] = segment_counts.get(a.segment or "No Segment", 0) + 1
            gender_counts[a.gender or "Unknown"] = gender_counts.get(a.gender or "Unknown", 0) + 1
            if a.days:
                day_counts[a.days] = day_counts.get(a.days, 0) + 1
            if a.sessions:
                session_counts[a.sessions] = session_counts.get(a.sessions, 0) + 1

        # ── Age buckets ──
        age_buckets: dict[str, int] = {"Under 5": 0, "5-7": 0, "8-10": 0, "11-13": 0, "14-17": 0, "18+": 0}
        ages: list[float] = []
        for a in athletes:
            if a.age_computed and 0 < a.age_computed < 100:
                ages.append(a.age_computed)
                if a.age_computed < 5: age_buckets["Under 5"] += 1
                elif a.age_computed < 8: age_buckets["5-7"] += 1
                elif a.age_computed < 11: age_buckets["8-10"] += 1
                elif a.age_computed < 14: age_buckets["11-13"] += 1
                elif a.age_computed < 18: age_buckets["14-17"] += 1
                else: age_buckets["18+"] += 1

        # ── Retention funnel — sorted highest to lowest, exclude "No Level" ──
        funnel = []
        sorted_levels = sorted(
            [(lvl, cnt) for lvl, cnt in level_counts.items() if cnt > 0 and lvl not in ("No Level", "Unknown")],
            key=lambda x: -x[1],
        )
        top_count = sorted_levels[0][1] if sorted_levels else 1
        for lvl, count in sorted_levels:
            pct_of_top = round(count / top_count * 100, 1) if top_count > 0 else 0
            funnel.append({"level": lvl, "count": count, "pct_of_top": pct_of_top})

        # ── Gender × Level (where are girls/boys dropping off?) ──
        gender_by_level: dict[str, dict[str, int]] = {}
        for a in athletes:
            if a.step and a.gender:
                gender_by_level.setdefault(a.step, {"M": 0, "F": 0})
                if a.gender in ("M", "F"):
                    gender_by_level[a.step][a.gender] += 1

        # ── Revenue by product type (paid = has pay value) ──
        revenue_by_type: dict[str, float] = {}
        revenue_by_segment: dict[str, float] = {}
        total_paid = 0.0
        paid_count = 0
        for a in athletes:
            if a.pay:
                try:
                    amount = float(Decimal(a.pay))
                    total_paid += amount
                    paid_count += 1
                    t = a.type or "Unknown"
                    revenue_by_type[t] = revenue_by_type.get(t, 0) + amount
                    s = a.segment or "No Segment"
                    revenue_by_segment[s] = revenue_by_segment.get(s, 0) + amount
                except (InvalidOperation, ValueError):
                    pass

        # ── Day/slot demand ──
        # Already in day_counts above

        # ── Coach load ──
        coach_load: dict[str, int] = {}
        for a in athletes:
            for s in a.schedule:
                if s.coach:
                    coach_load[s.coach] = coach_load.get(s.coach, 0) + 1

        # ── Data quality score ──
        total = len(athletes)
        data_quality = {
            "no_phone": sum(1 for a in athletes if not a.phone1),
            "no_dob": sum(1 for a in athletes if not a.date_of_birth),
            "no_level": sum(1 for a in athletes if not a.step),
            "no_type": sum(1 for a in athletes if not a.type),
            "no_gender": sum(1 for a in athletes if not a.gender),
            "no_days": sum(1 for a in athletes if not a.days),
            "total": total,
        }
        filled_fields = (total * 6) - sum(v for k, v in data_quality.items() if k != "total")
        data_quality["completeness_pct"] = round(filled_fields / (total * 6) * 100, 1) if total > 0 else 0

        analytics["branches"][bid] = {
            "name": roster.branch_name,
            "total_athletes": total,
            "collection": {
                "total_enrolled": total,
                "total_collected": total_paid,
                "paid_count": paid_count,
            },
            "retention_funnel": funnel,
            "enrollment_by_level": level_counts,
            "enrollment_by_type": type_counts,
            "segment_mix": segment_counts,
            "gender_split": gender_counts,
            "gender_by_level": gender_by_level,
            "age_buckets": age_buckets,
            "age_stats": {
                "min": round(min(ages), 1) if ages else None,
                "max": round(max(ages), 1) if ages else None,
                "avg": round(sum(ages) / len(ages), 1) if ages else None,
                "with_dob": len(ages),
                "missing_dob": total - len(ages),
            },
            "day_demand": day_counts,
            "session_counts": session_counts,
            "revenue_by_type": revenue_by_type,
            "revenue_by_segment": revenue_by_segment,
            "coach_load": coach_load,
            "data_quality": data_quality,
        }

    # Academy-wide aggregation
    if scope == "academy" and len(analytics["branches"]) > 1:
        totals = {
            "total_athletes": 0,
            "total_collected": 0.0,
            "paid_count": 0,
        }
        for b in analytics["branches"].values():
            totals["total_athletes"] += b["total_athletes"]
            totals["total_collected"] += b["collection"]["total_collected"]
            totals["paid_count"] += b["collection"]["paid_count"]
        analytics["academy_totals"] = totals

    return analytics


@router.get("/admin/discounts/flagged")
async def flagged_discounts(
    branch_id: Optional[int] = Query(None),
    admin: AdminUser = Depends(get_current_admin),
):
    """Return athletes whose Comment field contains discount-like text.

    These are surfaced as a flagged-for-review list — never as precise figures.
    """
    source = _get_roster_source()

    if branch_id:
        enforce_branch_scope(admin, branch_id)
        roster = await source.get_branch_roster(branch_id)
        rosters = {branch_id: roster} if roster else {}
    else:
        rosters = await source.get_all_rosters()
        if admin.role == "assistant":
            rosters = {k: v for k, v in rosters.items() if k == admin.assigned_branch_id}

    flagged = []
    for bid, roster in rosters.items():
        for a in roster.athletes:
            if a.comment and _DISCOUNT_PATTERNS.search(a.comment):
                flagged.append({
                    "branch": roster.branch_name,
                    "branch_id": bid,
                    "athlete_number": a.athlete_number,
                    "name": a.name,
                    "comment": a.comment,
                    "pay": a.pay,
                })

    return {"count": len(flagged), "flagged": flagged}


@router.get("/admin/receipts/{receipt_id}/pdf")
async def admin_download_receipt_pdf(
    receipt_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Download a receipt PDF (admin access)."""
    result = await db.execute(select(Receipt).where(Receipt.id == receipt_id))
    receipt = result.scalar_one_or_none()
    if not receipt or not receipt.pdf_data:
        raise HTTPException(status_code=404, detail="Receipt not found")

    # Scope check via payment
    payment_result = await db.execute(select(Payment).where(Payment.id == receipt.payment_id))
    payment = payment_result.scalar_one_or_none()
    if payment:
        enforce_branch_scope(admin, payment.branch_id)

    return Response(
        content=receipt.pdf_data,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="receipt_{receipt.receipt_number}.pdf"'},
    )


@router.get("/admin/health/excel")
async def excel_health(admin: AdminUser = Depends(get_current_admin)):
    source = _get_roster_source()
    return source.get_health()
