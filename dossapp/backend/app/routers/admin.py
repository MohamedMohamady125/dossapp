"""Admin/Assistant endpoints — branches, athletes, provisioning, payments, analytics, health."""

import re
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from pydantic import BaseModel

from app.database import get_db
from app.models.account import Account
from app.models.admin_user import AdminUser
from app.models.branch import Branch
from app.models.payment import Payment
from app.models.receipt import Receipt
from app.routers.deps import get_current_admin, enforce_branch_scope
from app.schemas.athlete import AthleteDetail, ProvisionRequest, ProvisionResponse, ScheduleSlot
from app.schemas.notification import TestSendRequest
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


# ── Branch management schemas ──────────────────────────────────────────

class BranchCreate(BaseModel):
    name: str
    display_name: str
    drive_file_id: Optional[str] = None


class BranchUpdate(BaseModel):
    name: Optional[str] = None
    display_name: Optional[str] = None
    drive_file_id: Optional[str] = None


class BranchOut(BaseModel):
    id: int
    name: str
    display_name: str
    drive_file_id: Optional[str] = None

    class Config:
        from_attributes = True


# ── Branch management endpoints (admin-only) ──────────────────────────

def _require_admin_role(admin: AdminUser):
    if admin.role != "admin":
        raise HTTPException(status_code=403, detail="Admin role required")


@router.get("/admin/branches/manage", response_model=list[BranchOut])
async def list_branches_manage(
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """List all branches from DB with full config details."""
    _require_admin_role(admin)
    result = await db.execute(select(Branch).order_by(Branch.id))
    return result.scalars().all()


@router.post("/admin/branches", response_model=BranchOut, status_code=201)
async def create_branch(
    payload: BranchCreate,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Create a new branch, register it in roster source, and trigger initial refresh."""
    _require_admin_role(admin)

    # Check unique name
    existing = await db.execute(select(Branch).where(Branch.name == payload.name))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Branch name already exists")

    branch = Branch(name=payload.name, display_name=payload.display_name, drive_file_id=payload.drive_file_id or None)
    db.add(branch)
    await db.commit()
    await db.refresh(branch)

    # Update roster source config and refresh (after commit so DB connection isn't held during Drive download)
    source = _get_roster_source()
    source.update_config(branch.id, {
        "branch_id": branch.id,
        "branch_name": branch.display_name,
        "drive_file_id": branch.drive_file_id,
    })
    if branch.drive_file_id:
        await source.refresh_branch(branch.id)

    return branch


@router.put("/admin/branches/{branch_id}", response_model=BranchOut)
async def update_branch(
    branch_id: int,
    payload: BranchUpdate,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Update a branch's name, display_name, or drive_file_id."""
    _require_admin_role(admin)

    result = await db.execute(select(Branch).where(Branch.id == branch_id))
    branch = result.scalar_one_or_none()
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found")

    old_drive_file_id = branch.drive_file_id

    if payload.name is not None:
        # Check unique name (excluding self)
        dup = await db.execute(select(Branch).where(Branch.name == payload.name, Branch.id != branch_id))
        if dup.scalar_one_or_none():
            raise HTTPException(status_code=409, detail="Branch name already exists")
        branch.name = payload.name
    if payload.display_name is not None:
        branch.display_name = payload.display_name
    if payload.drive_file_id is not None:
        branch.drive_file_id = payload.drive_file_id or None  # empty string → NULL

    db.add(branch)

    await db.commit()
    await db.refresh(branch)

    # Update roster source config (after commit so DB connection isn't held during Drive download)
    source = _get_roster_source()
    source.update_config(branch.id, {
        "branch_id": branch.id,
        "branch_name": branch.display_name,
        "drive_file_id": branch.drive_file_id,
    })

    # Refresh if drive_file_id changed
    if branch.drive_file_id and branch.drive_file_id != old_drive_file_id:
        await source.refresh_branch(branch.id)

    return branch


@router.delete("/admin/branches/{branch_id}")
async def delete_branch(
    branch_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Delete a branch from DB and remove from roster source."""
    _require_admin_role(admin)

    result = await db.execute(select(Branch).where(Branch.id == branch_id))
    branch = result.scalar_one_or_none()
    if not branch:
        raise HTTPException(status_code=404, detail="Branch not found")

    await db.delete(branch)
    await db.commit()

    source = _get_roster_source()
    source.remove_config(branch_id)

    return {"message": "Branch deleted"}


# ── Price catalog schemas ─────────────────────────────────────────────

class PriceCatalogCreate(BaseModel):
    branch_id: int
    program_name: str
    segment: Optional[str] = None
    sessions: Optional[str] = None
    price: str  # Decimal as string

class PriceCatalogUpdate(BaseModel):
    program_name: Optional[str] = None
    segment: Optional[str] = None
    sessions: Optional[str] = None
    price: Optional[str] = None
    is_active: Optional[bool] = None

class PriceCatalogOut(BaseModel):
    id: int
    branch_id: int
    program_name: str
    segment: Optional[str] = None
    sessions: Optional[str] = None
    price: str
    is_active: bool

    class Config:
        from_attributes = True


# ── Price catalog endpoints (admin-only) ──────────────────────────────

@router.get("/admin/price-catalog", response_model=list[PriceCatalogOut])
async def list_price_catalog(
    branch_id: Optional[int] = Query(None),
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    _require_admin_role(admin)
    from app.models.price_catalog import PriceCatalog

    query = select(PriceCatalog).where(PriceCatalog.is_active == True)  # noqa: E712
    if branch_id:
        query = query.where(PriceCatalog.branch_id == branch_id)
    query = query.order_by(PriceCatalog.branch_id, PriceCatalog.program_name)

    result = await db.execute(query)
    entries = result.scalars().all()
    return [
        PriceCatalogOut(
            id=e.id, branch_id=e.branch_id, program_name=e.program_name,
            segment=e.segment, sessions=e.sessions,
            price=str(e.price), is_active=e.is_active,
        )
        for e in entries
    ]


@router.post("/admin/price-catalog", status_code=201)
async def create_price_catalog_entry(
    payload: PriceCatalogCreate,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    _require_admin_role(admin)
    from app.models.price_catalog import PriceCatalog
    from decimal import Decimal, InvalidOperation

    try:
        price = Decimal(payload.price)
    except (InvalidOperation, ValueError):
        raise HTTPException(status_code=400, detail="Invalid price value")

    entry = PriceCatalog(
        branch_id=payload.branch_id,
        program_name=payload.program_name.strip(),
        segment=payload.segment.strip() if payload.segment else None,
        sessions=payload.sessions.strip() if payload.sessions else None,
        price=price,
    )
    db.add(entry)
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Duplicate catalog entry")
    await db.refresh(entry)
    return PriceCatalogOut(
        id=entry.id, branch_id=entry.branch_id, program_name=entry.program_name,
        segment=entry.segment, sessions=entry.sessions,
        price=str(entry.price), is_active=entry.is_active,
    )


@router.put("/admin/price-catalog/{entry_id}")
async def update_price_catalog_entry(
    entry_id: int,
    payload: PriceCatalogUpdate,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    _require_admin_role(admin)
    from app.models.price_catalog import PriceCatalog
    from decimal import Decimal, InvalidOperation

    result = await db.execute(select(PriceCatalog).where(PriceCatalog.id == entry_id))
    entry = result.scalar_one_or_none()
    if not entry:
        raise HTTPException(status_code=404, detail="Catalog entry not found")

    if payload.program_name is not None:
        entry.program_name = payload.program_name.strip()
    if payload.segment is not None:
        entry.segment = payload.segment.strip() or None
    if payload.sessions is not None:
        entry.sessions = payload.sessions.strip() or None
    if payload.price is not None:
        try:
            entry.price = Decimal(payload.price)
        except (InvalidOperation, ValueError):
            raise HTTPException(status_code=400, detail="Invalid price value")
    if payload.is_active is not None:
        entry.is_active = payload.is_active

    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    return PriceCatalogOut(
        id=entry.id, branch_id=entry.branch_id, program_name=entry.program_name,
        segment=entry.segment, sessions=entry.sessions,
        price=str(entry.price), is_active=entry.is_active,
    )


@router.delete("/admin/price-catalog/{entry_id}")
async def delete_price_catalog_entry(
    entry_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    _require_admin_role(admin)
    from app.models.price_catalog import PriceCatalog

    result = await db.execute(select(PriceCatalog).where(PriceCatalog.id == entry_id))
    entry = result.scalar_one_or_none()
    if not entry:
        raise HTTPException(status_code=404, detail="Catalog entry not found")

    await db.delete(entry)
    await db.commit()
    return {"message": "Catalog entry deleted"}


@router.get("/admin/price-catalog/missing")
async def list_missing_prices(
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Find athlete programs that have no matching price catalog entry."""
    _require_admin_role(admin)
    from app.services.price_resolver import load_branch_catalog, resolve_price_from_catalog, _normalize_program_name

    source = _get_roster_source()
    rosters = await source.get_all_rosters()

    missing = []  # [{branch_id, branch_name, program_name, athlete_count, sample_athletes}]

    for bid, roster in rosters.items():
        catalog = await load_branch_catalog(db, bid)

        # Group athletes by their resolved program name
        unpriced: dict[str, list[str]] = {}  # program_name -> [athlete names]
        for a in roster.athletes:
            bill = resolve_price_from_catalog(catalog, a.type, a.step, a.segment, a.sessions)
            if bill is not None:
                continue
            # Find what program name would match
            candidates = _normalize_program_name(a.type, a.step)
            label = candidates[0] if candidates else (a.type or "Unknown")
            # Include type + step info for context
            detail = f"{a.type or '—'} / {a.step or '—'}"
            key = f"{label} ({detail})" if detail != "— / —" else label
            unpriced.setdefault(key, []).append(a.name)

        for program_key, names in unpriced.items():
            missing.append({
                "branch_id": bid,
                "branch_name": roster.branch_name,
                "program_label": program_key,
                "athlete_count": len(names),
                "sample_athletes": names[:5],
            })

    # Sort by branch then by athlete count descending
    missing.sort(key=lambda x: (x["branch_id"], -x["athlete_count"]))
    return missing


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


@router.get("/admin/coaches")
async def list_coach_accounts(
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """List auto-provisioned coach accounts so the admin can hand out credentials."""
    query = select(AdminUser).where(AdminUser.role == "coach")
    if admin.role == "assistant":
        query = query.where(AdminUser.assigned_branch_id == admin.assigned_branch_id)
    result = await db.execute(query.order_by(AdminUser.assigned_branch_id, AdminUser.coach_name))

    return [
        {
            "id": c.id,
            "username": c.username,
            "coach_name": c.coach_name,
            "branch_id": c.assigned_branch_id,
            "is_active": c.is_active,
            "must_change_password": c.must_change_password,
            "last_login_at": c.last_login_at.isoformat() if c.last_login_at else None,
        }
        for c in result.scalars().all()
    ]


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

    # Resolve bills from price catalog (single DB query for entire branch)
    from app.services.price_resolver import load_branch_catalog, resolve_price_from_catalog
    catalog = await load_branch_catalog(db, branch_id)
    athletes_out = []
    for a in roster.athletes:
        bill = resolve_price_from_catalog(catalog, a.type, a.step, a.segment, a.sessions)
        athletes_out.append(AthleteDetail(
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
            bill=str(bill) if bill else None,
            phone1=a.phone1,
            phone2=a.phone2,
            comment=a.comment,
            receipt_no=a.receipt_no,
            has_account=a.athlete_number in provisioned,
            schedule=[
                ScheduleSlot(coach=s.coach, time_block=s.time_block, day_pair=s.day_pair)
                for s in a.schedule
            ],
        ))
    return athletes_out


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
        attendance=athlete.attendance,
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


class MarkPaidBody(BaseModel):
    payment_method: str = "cash"  # "cash" | "card"


@router.post("/branches/{branch_id}/athletes/{athlete_number}/mark-paid")
async def mark_athlete_paid(
    branch_id: int,
    athlete_number: int,
    body: MarkPaidBody = MarkPaidBody(),
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

    period = datetime.now().strftime("%Y-%m")

    # Determine bill amount from catalog, then Excel pay, then fail
    from app.services.price_resolver import resolve_price
    catalog_price = await resolve_price(
        db, branch_id, athlete.type, athlete.step, athlete.segment, athlete.sessions
    )

    if catalog_price is not None:
        bill_amount = catalog_price
    elif athlete.pay:
        bill_amount = Decimal(athlete.pay)
    else:
        raise HTTPException(status_code=400, detail="No bill amount set for this athlete")

    from app.services.payment_service import record_manual_payment
    receipt = await record_manual_payment(
        db=db,
        branch_id=branch_id,
        athlete_number=athlete_number,
        period=period,
        amount_paid=bill_amount,
        amount_owed=bill_amount,
        athlete_name=athlete.name,
        branch_name=roster.branch_name,
        level=athlete.step,
        athlete_type=athlete.type,
        phone=athlete.phone1,
        payment_method=body.payment_method,
    )

    if not receipt:
        raise HTTPException(status_code=400, detail="Already paid for this period")

    return {"message": "Marked as paid", "receipt_number": receipt.receipt_number, "receipt_id": receipt.id}


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

    # Batch-fetch receipts for all payments
    payment_ids = [p.id for p in payments]
    receipt_map = {}
    if payment_ids:
        receipt_result = await db.execute(
            select(Receipt).where(Receipt.payment_id.in_(payment_ids))
        )
        receipt_map = {r.payment_id: r for r in receipt_result.scalars().all()}

    out = []
    for p in payments:
        athlete = athlete_map.get(p.athlete_number)
        receipt = receipt_map.get(p.id)

        # Extract coach + training time from first schedule slot
        coach_name = None
        training_time = None
        if athlete and athlete.schedule:
            slot = athlete.schedule[0]
            coach_name = slot.coach
            parts = []
            if slot.day_pair:
                parts.append(slot.day_pair)
            if slot.time_block:
                parts.append(slot.time_block)
            training_time = " ".join(parts) if parts else None

        out.append(PaymentOut(
            id=p.id,
            branch_id=p.branch_id,
            athlete_number=p.athlete_number,
            athlete_name=athlete.name if athlete else f"Athlete #{p.athlete_number}",
            level=athlete.step if athlete else None,
            athlete_type=athlete.type if athlete else None,
            period=p.period,
            source=p.source,
            amount_paid=str(p.amount_paid),
            status=p.status,
            paid_at=p.paid_at,
            payment_channel=receipt.payment_channel if receipt else None,
            receipt_number=receipt.receipt_number if receipt else None,
            receipt_id=receipt.id if receipt else None,
            coach=coach_name,
            training_time=training_time,
        ))
    return out


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


@router.post("/admin/notifications/test-send")
async def test_send_notification(
    payload: TestSendRequest,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """Send a test push+inbox notification to a customer account (dry_run uses FCM validate_only)."""
    enforce_branch_scope(admin, payload.branch_id)

    result = await db.execute(
        select(Account).where(
            Account.branch_id == payload.branch_id,
            Account.athlete_number == payload.athlete_number,
        )
    )
    account = result.scalar_one_or_none()
    if not account:
        raise HTTPException(status_code=404, detail="No customer account for that athlete")

    from app.models.push import DeviceToken
    from app.services.push_service import send_fcm, send_push_to_account, push_configured

    if payload.dry_run:
        tokens_result = await db.execute(
            select(DeviceToken).where(DeviceToken.account_id == account.id, DeviceToken.is_active == True)  # noqa: E712
        )
        tokens = tokens_result.scalars().all()
        results = []
        for device in tokens:
            ok, error = await send_fcm(device.token, payload.title, payload.body, validate_only=True)
            results.append({"platform": device.platform, "ok": ok, "error": error})
        return {
            "dry_run": True,
            "push_configured": push_configured(),
            "devices": len(tokens),
            "results": results,
        }

    await send_push_to_account(db, account.id, "test", payload.title, payload.body)
    return {"dry_run": False, "message": "Notification sent"}


# ── Reinstatement Requests ──


class DeclineBody(BaseModel):
    admin_note: Optional[str] = None


@router.get("/admin/reinstatement-requests")
async def list_reinstatement_requests(
    status_filter: Optional[str] = Query("pending"),
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """List reinstatement requests with athlete context."""
    from app.models.reinstatement_request import ReinstatementRequest

    query = select(ReinstatementRequest)
    if status_filter:
        query = query.where(ReinstatementRequest.status == status_filter)
    # Scope assistants to their branch
    if admin.role != "admin" and admin.assigned_branch_id:
        query = query.where(ReinstatementRequest.branch_id == admin.assigned_branch_id)
    query = query.order_by(ReinstatementRequest.created_at.desc())

    result = await db.execute(query)
    requests = result.scalars().all()

    source = _get_roster_source()
    items = []
    for req in requests:
        roster = await source.get_branch_roster(req.branch_id)
        athlete = None
        if roster:
            athlete = next((a for a in roster.athletes if a.athlete_number == req.athlete_number), None)

        # Check payment status
        from app.models.payment import Payment
        period = datetime.now().strftime("%Y-%m")
        paid_result = await db.execute(
            select(Payment.id).where(
                Payment.branch_id == req.branch_id,
                Payment.athlete_number == req.athlete_number,
                Payment.period == period,
                Payment.status == "paid",
            )
        )
        is_paid = paid_result.scalar_one_or_none() is not None

        items.append({
            "id": req.id,
            "account_id": req.account_id,
            "branch_id": req.branch_id,
            "branch_name": roster.branch_name if roster else f"Branch {req.branch_id}",
            "athlete_number": req.athlete_number,
            "athlete_name": athlete.name if athlete else "Unknown",
            "status": req.status,
            "message": req.message,
            "admin_note": req.admin_note,
            "created_at": req.created_at.isoformat() if req.created_at else None,
            "reviewed_at": req.reviewed_at.isoformat() if req.reviewed_at else None,
            "attendance": dict(sorted(athlete.attendance.items())) if athlete and athlete.attendance else {},
            "sessions": athlete.sessions if athlete else None,
            "is_paid": is_paid,
        })

    return items


@router.post("/admin/reinstatement-requests/{request_id}/approve")
async def approve_reinstatement(
    request_id: int,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    from app.models.reinstatement_request import ReinstatementRequest

    result = await db.execute(select(ReinstatementRequest).where(ReinstatementRequest.id == request_id))
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
    enforce_branch_scope(admin, req.branch_id)

    if req.status != "pending":
        raise HTTPException(status_code=400, detail=f"Request already {req.status}")

    req.status = "approved"
    req.reviewed_by = admin.id
    req.reviewed_at = datetime.now()

    # Reactivate account
    acc_result = await db.execute(select(Account).where(Account.id == req.account_id))
    account = acc_result.scalar_one_or_none()
    if account:
        account.status = "active"
        db.add(account)

    db.add(req)
    await db.commit()

    # Notify user
    if account:
        from app.services.push_service import send_push_to_account
        await send_push_to_account(
            db, account.id, "reinstatement_approved",
            "Reinstatement Approved",
            "Your reinstatement request has been approved! You can now use the app normally.",
            data={"screen": "home"},
        )

    return {"message": "Reinstatement approved"}


@router.post("/admin/reinstatement-requests/{request_id}/decline")
async def decline_reinstatement(
    request_id: int,
    body: DeclineBody,
    admin: AdminUser = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    from app.models.reinstatement_request import ReinstatementRequest

    result = await db.execute(select(ReinstatementRequest).where(ReinstatementRequest.id == request_id))
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
    enforce_branch_scope(admin, req.branch_id)

    if req.status != "pending":
        raise HTTPException(status_code=400, detail=f"Request already {req.status}")

    req.status = "declined"
    req.admin_note = body.admin_note or "Your spot has been taken because you didn't show up and didn't pay."
    req.reviewed_by = admin.id
    req.reviewed_at = datetime.now()
    db.add(req)
    await db.commit()

    # Notify user
    acc_result = await db.execute(select(Account).where(Account.id == req.account_id))
    account = acc_result.scalar_one_or_none()
    if account:
        from app.services.push_service import send_push_to_account
        await send_push_to_account(
            db, account.id, "reinstatement_declined",
            "Reinstatement Declined",
            req.admin_note,
            data={"screen": "home"},
        )

    return {"message": "Reinstatement declined"}

