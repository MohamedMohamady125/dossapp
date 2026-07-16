"""Aqua Athletic — FastAPI application entry point."""

import asyncio
import logging

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.config import settings
from app.database import async_session, engine
from app.models.branch import Branch
from app.routers import auth, customer, admin, coach, cron, notifications, webhooks
from app.services.excel_roster_source import ExcelRosterSource
from app.services.reconciliation import reconcile_branch
from app.services.identity_guard import check_identity_mismatches
from app.services.snapshot import save_roster_snapshot
from app.services.notifications import process_notification_queue

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)

# Will be populated from DB on startup
roster_source: ExcelRosterSource = ExcelRosterSource([])


async def _load_branch_configs() -> list[dict]:
    """Load branch configs from DB, falling back to settings-based config."""
    configs = []
    try:
        async with async_session() as db:
            result = await db.execute(select(Branch))
            branches = result.scalars().all()
            for branch in branches:
                if branch.drive_file_id:
                    configs.append({
                        "branch_id": branch.id,
                        "branch_name": branch.display_name or branch.name,
                        "drive_file_id": branch.drive_file_id,
                    })
    except Exception as e:
        logger.warning(f"Could not load branches from DB: {e}")

    # Fallback to settings if DB has no branches with Drive IDs
    if not configs:
        branch_names = {
            1: "Rehab", 2: "Choueifat Cairo", 3: "Choueifat",
            4: "Madinaty", 5: "Branch 5", 6: "Branch 6", 7: "Branch 7",
        }
        for i in range(1, 8):
            file_id = getattr(settings, f"drive_file_id_branch_{i}", "")
            if file_id:
                configs.append({
                    "branch_id": i,
                    "branch_name": branch_names.get(i, f"Branch {i}"),
                    "drive_file_id": file_id,
                })

    # Local dev mode: if no Drive configs, use sample workbook for branch 1
    if not configs:
        import os
        sample_path = os.path.join(os.path.dirname(__file__), "..", "tests", "sample_workbook.xlsx")
        sample_path = os.path.abspath(sample_path)
        if os.path.exists(sample_path):
            logger.info(f"Dev mode: loading sample workbook from {sample_path}")
            configs.append({
                "branch_id": 1,
                "branch_name": "Branch 1",
                "local_file_path": sample_path,
            })

    return configs


async def _refresh_and_reconcile():
    """Periodic Excel refresh + cash reconciliation + identity guard."""
    while True:
        try:
            changed = await roster_source.refresh_all()
            for branch_id, did_change in changed.items():
                if did_change:
                    roster = await roster_source.get_branch_roster(branch_id)
                    if roster:
                        async with async_session() as db:
                            # Cash reconciliation
                            count = await reconcile_branch(roster, db)
                            if count > 0:
                                logger.info(f"Reconciled {count} cash payments for branch {branch_id}")

                        async with async_session() as db:
                            # Provision coach login accounts for new coaches
                            from app.services.coach_accounts import sync_coach_accounts
                            new_coaches = await sync_coach_accounts(roster, db)
                            if new_coaches > 0:
                                logger.info(f"Created {new_coaches} coach accounts for branch {branch_id}")

                        async with async_session() as db:
                            # Identity guard — detect athlete number reuse
                            mismatches = await check_identity_mismatches(roster, db)
                            if mismatches > 0:
                                logger.warning(f"Detected {mismatches} identity mismatches for branch {branch_id}")

                        # Tier 3: save period-stamped snapshot (once per day per branch)
                        try:
                            async with async_session() as db:
                                await save_roster_snapshot(roster, db)
                        except Exception as e:
                            logger.error(f"Snapshot save error for branch {branch_id}: {e}")

                        # Push notifications: schedule changes + missed sessions
                        try:
                            from app.services.push_triggers import run_roster_triggers
                            async with async_session() as db:
                                counts = await run_roster_triggers(roster, db)
                                if counts["schedule"] or counts["missed"]:
                                    logger.info(f"Push triggers branch {branch_id}: {counts}")
                        except Exception as e:
                            logger.error(f"Push trigger error for branch {branch_id}: {e}")
        except Exception as e:
            logger.error(f"Refresh/reconciliation error: {e}")

        await asyncio.sleep(settings.excel_refresh_interval_seconds)


async def _auto_seed():
    """Seed admin user and branches if the DB is empty (for Vercel ephemeral SQLite)."""
    from app.models.admin_user import AdminUser
    from app.utils.auth import hash_password

    try:
        async with async_session() as db:
            existing_admin = await db.execute(select(AdminUser))
            if existing_admin.scalars().first():
                return  # Already seeded

            # Seed branches with real names
            branch_defs = [
                ("rehab", "Rehab"),
                ("choueifat_cairo", "Choueifat Cairo"),
                ("choueifat", "Choueifat"),
                ("madinaty", "Madinaty"),
                ("branch_5", "Branch 5"),
                ("branch_6", "Branch 6"),
                ("branch_7", "Branch 7"),
            ]
            for i, (name, display_name) in enumerate(branch_defs, 1):
                drive_id = getattr(settings, f"drive_file_id_branch_{i}", "")
                branch = Branch(
                    name=name,
                    display_name=display_name,
                    drive_file_id=drive_id or None,
                )
                db.add(branch)

            # Seed admin user
            admin = AdminUser(
                username="admin",
                email="admin@aquaathletic.com",
                password_hash=hash_password("admin123"),
                role="admin",
                is_active=True,
            )
            db.add(admin)
            await db.commit()
            logger.info("Auto-seeded admin user and branches")
    except Exception as e:
        logger.error(f"Auto-seed error: {e}")

    # Seed price catalog (idempotent — skips if entries exist)
    await _seed_price_catalog()


async def _seed_price_catalog():
    """Seed price catalog from the official pricing PDF. Idempotent."""
    from app.models.price_catalog import PriceCatalog
    from decimal import Decimal

    try:
        async with async_session() as db:
            existing = await db.execute(select(PriceCatalog).limit(1))
            if existing.scalars().first():
                return  # Already seeded

            entries = []

            # ── Branch 1: Rehab (GEMS) — flat pricing ──
            for prog, price in [
                ("Level One", 1500), ("Group Training", 1250),
                ("Semi-Private Training", 2200), ("Private Training", 3500),
            ]:
                entries.append(PriceCatalog(branch_id=1, program_name=prog, price=Decimal(price)))

            # ── Branch 4: Madinaty (BISM) — same flat pricing ──
            for prog, price in [
                ("Level One", 1500), ("Group Training", 1250),
                ("Semi-Private Training", 2200), ("Private Training", 3500),
            ]:
                entries.append(PriceCatalog(branch_id=4, program_name=prog, price=Decimal(price)))

            # ── Branch 2: Choueifat Cairo (New Cairo) — student vs outsider ──
            nc_prices = [
                ("Group Training",          1100, 1300),
                ("Adult Training",          1250, 1500),
                ("Pre-Team",                1600, 1800),
                ("Private Training",        3000, 3300),
                ("Semi-Private 2",          2000, 2300),
                ("Semi-Private 3",          1500, 1750),
                ("Baby Classes - Group",    1500, 1750),
                ("Baby Classes - Private",  3000, 3500),
            ]
            for prog, student, outsider in nc_prices:
                entries.append(PriceCatalog(branch_id=2, program_name=prog, segment="Student", price=Decimal(student)))
                entries.append(PriceCatalog(branch_id=2, program_name=prog, segment="Outsider", price=Decimal(outsider)))

            # ── Branch 3: Choueifat (October) — student vs outsider + sessions ──
            oct_prices = [
                ("Step 1-6",        "1 Session",  160,  180),
                ("Step 1-6",        "8 Sessions", 1100, 1250),
                ("Adult Training",  "1 Session",  200,  200),
                ("Adult Training",  "8 Sessions", 1450, 1450),
                ("Pre-Team",        "1 Week",     450,  500),
                ("Pre-Team",        "4 Weeks",    1500, 1700),
                ("Junior Team",     "1 Week",     500,  600),
                ("Junior Team",     "4 Weeks",    1800, 2000),
                ("Elite Team",      "1 Week",     700,  800),
                ("Elite Team",      "4 Weeks",    2500, 2800),
                ("Private 1-to-1",  "1 Session",  340,  375),
                ("Private 1-to-1",  "8 Sessions", 2700, 3000),
                ("Semi-Private 2",  "1 Session",  250,  290),
                ("Semi-Private 2",  "8 Sessions", 2000, 2300),
                ("Semi-Private 3",  "1 Session",  190,  225),
                ("Semi-Private 3",  "8 Sessions", 1500, 1800),
            ]
            for prog, sess, student, outsider in oct_prices:
                entries.append(PriceCatalog(branch_id=3, program_name=prog, segment="Student", sessions=sess, price=Decimal(student)))
                entries.append(PriceCatalog(branch_id=3, program_name=prog, segment="Outsider", sessions=sess, price=Decimal(outsider)))

            db.add_all(entries)
            await db.commit()
            logger.info(f"Seeded {len(entries)} price catalog entries")
    except Exception as e:
        logger.error(f"Price catalog seed error: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    global roster_source

    logger.info("Starting Aqua Athletic backend...")

    # Auto-create tables for SQLite dev mode
    from app.database import init_db
    await init_db()

    # Auto-seed admin user and branches if DB is empty (needed for Vercel /tmp SQLite)
    await _auto_seed()

    # Load branch configs from DB
    configs = await _load_branch_configs()
    roster_source = ExcelRosterSource(configs)

    import os
    is_serverless = os.environ.get("VERCEL") or os.environ.get("AWS_LAMBDA_FUNCTION_NAME")

    # Always pre-load Excel data so the first request is fast.
    # Reconciliation/coach sync/push triggers run only via cron.
    if configs:
        await roster_source.refresh_all()
        logger.info(f"Initial Excel load complete ({len(configs)} branches)")

    # Skip background tasks in serverless (Vercel) — no long-running processes
    refresh_task = None
    notification_task = None
    if not is_serverless:
        refresh_task = asyncio.create_task(_refresh_and_reconcile())
        notification_task = asyncio.create_task(process_notification_queue(async_session))

    yield

    if refresh_task:
        refresh_task.cancel()
    if notification_task:
        notification_task.cancel()
    logger.info("Aqua Athletic backend shutting down")


app = FastAPI(
    title="Aqua Athletic Academy",
    version="1.0.0",
    description="Backend API for Aqua Athletic Academy management app",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO(spec): Restrict to Flutter app domain in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(auth.router)
app.include_router(customer.router)
app.include_router(admin.router)
app.include_router(coach.router)
app.include_router(cron.router)
app.include_router(notifications.router)
app.include_router(webhooks.router)
app.include_router(webhooks.success_router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "aqua-athletic"}


