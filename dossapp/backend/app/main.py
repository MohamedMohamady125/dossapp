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
            file_id = getattr(settings, f"drive_file_id_branch_{i}", "").strip()
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
                drive_id = getattr(settings, f"drive_file_id_branch_{i}", "").strip()
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
    await _patch_missing_catalog_entries()


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
                ("Adult Training", 1250), ("Pre-Team", 1700),
                ("Semi-Private Training", 2200), ("Semi-Private 2", 2200), ("Semi-Private 3", 2200),
                ("Private Training", 3500), ("Private 1-to-1", 3500),
            ]:
                entries.append(PriceCatalog(branch_id=1, program_name=prog, price=Decimal(price)))

            # ── Branch 4: Madinaty (BISM) — same flat pricing ──
            for prog, price in [
                ("Level One", 1500), ("Group Training", 1250),
                ("Adult Training", 1250), ("Pre-Team", 1700),
                ("Semi-Private Training", 2200), ("Semi-Private 2", 2200), ("Semi-Private 3", 2200),
                ("Private Training", 3500), ("Private 1-to-1", 3500),
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


async def _patch_missing_catalog_entries():
    """Add catalog entries that were missing from the initial seed."""
    from app.models.price_catalog import PriceCatalog
    from decimal import Decimal

    # (branch_id, program_name, segment, sessions, price)
    patches = [
        # Branch 1 (Rehab) — missing programs
        (1, "Adult Training", None, None, 1250),
        (1, "Pre-Team", None, None, 1700),
        (1, "Semi-Private 2", None, None, 2200),
        (1, "Semi-Private 3", None, None, 2200),
        (1, "Private 1-to-1", None, None, 3500),
        # Branch 4 (Madinaty) — same missing programs
        (4, "Adult Training", None, None, 1250),
        (4, "Pre-Team", None, None, 1700),
        (4, "Semi-Private 2", None, None, 2200),
        (4, "Semi-Private 3", None, None, 2200),
        (4, "Private 1-to-1", None, None, 3500),
    ]

    try:
        async with async_session() as db:
            added = 0
            for branch_id, prog, seg, sess, price in patches:
                # Check if entry already exists
                q = select(PriceCatalog).where(
                    PriceCatalog.branch_id == branch_id,
                    PriceCatalog.program_name == prog,
                )
                if seg is not None:
                    q = q.where(PriceCatalog.segment == seg)
                else:
                    q = q.where(PriceCatalog.segment.is_(None))
                if sess is not None:
                    q = q.where(PriceCatalog.sessions == sess)
                else:
                    q = q.where(PriceCatalog.sessions.is_(None))

                result = await db.execute(q)
                if result.scalar_one_or_none():
                    continue

                db.add(PriceCatalog(
                    branch_id=branch_id, program_name=prog,
                    segment=seg, sessions=sess, price=Decimal(price),
                ))
                added += 1

            if added:
                await db.commit()
                logger.info(f"Patched {added} missing price catalog entries")
    except Exception as e:
        logger.error(f"Patch catalog error: {e}")


async def _sync_drive_file_ids():
    """Seed branch drive_file_id from env vars only if DB value is empty.

    Never overwrite admin-set values — the DB is the source of truth once set.
    """
    try:
        async with async_session() as db:
            result = await db.execute(select(Branch))
            branches = result.scalars().all()
            for branch in branches:
                env_file_id = getattr(settings, f"drive_file_id_branch_{branch.id}", "").strip()
                current = (branch.drive_file_id or "").strip()
                # Only fill in if DB is empty and env var has a value
                if env_file_id and not current:
                    branch.drive_file_id = env_file_id
                    logger.info(f"Seeded drive_file_id for branch {branch.id} ({branch.display_name})")
            await db.commit()
    except Exception as e:
        logger.error(f"Sync drive file IDs error: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    global roster_source

    logger.info("Starting Aqua Athletic backend...")

    # Auto-create tables for SQLite dev mode
    from app.database import init_db
    await init_db()

    # Auto-seed admin user and branches if DB is empty (needed for Vercel /tmp SQLite)
    await _auto_seed()

    # Sync drive file IDs from env vars into DB branches (in case they changed)
    await _sync_drive_file_ids()

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


from fastapi.responses import HTMLResponse

@app.get("/privacy", response_class=HTMLResponse)
async def privacy_policy():
    return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Aquathletic - Privacy Policy</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; color: #333; line-height: 1.6; }
h1 { color: #1565C0; }
h2 { color: #1976D2; margin-top: 24px; }
p, li { font-size: 15px; }
.updated { color: #666; font-size: 13px; }
</style>
</head>
<body>
<h1>Aquathletic Privacy Policy</h1>
<p class="updated">Last updated: August 9, 2026</p>

<h2>1. Information We Collect</h2>
<p>We collect the following information when you use the Aquathletic app:</p>
<ul>
<li><strong>Account Information:</strong> Name, email address, phone number, and login credentials provided during registration.</li>
<li><strong>Athlete Data:</strong> Swimmer name, age, date of birth, gender, class type, level, attendance records, and branch enrollment details.</li>
<li><strong>Payment Information:</strong> Payment status, billing amounts, receipt records, and payment method (online, cash, or card). We do not store credit card numbers directly — online payments are processed by our third-party payment provider (EasyKash).</li>
<li><strong>Device Information:</strong> Device tokens for push notifications (Firebase Cloud Messaging).</li>
</ul>

<h2>2. How We Use Your Information</h2>
<ul>
<li>To manage your swimming academy enrollment and attendance.</li>
<li>To generate and deliver payment bills and receipts.</li>
<li>To send push notifications about payment reminders, schedule changes, and academy announcements.</li>
<li>To send verification emails for account security.</li>
<li>To provide coaches and administrators with class management tools.</li>
</ul>

<h2>3. Information Sharing</h2>
<p>We do not sell your personal information. We share data only with:</p>
<ul>
<li><strong>Payment Processors:</strong> EasyKash for processing online payments.</li>
<li><strong>Email Services:</strong> Resend for sending transactional emails (verification codes, receipts).</li>
<li><strong>Push Notification Services:</strong> Firebase Cloud Messaging for delivering notifications.</li>
<li><strong>Academy Staff:</strong> Coaches and administrators can view athlete enrollment, attendance, and payment status relevant to their branch.</li>
</ul>

<h2>4. Data Security</h2>
<p>We use industry-standard security measures including encrypted passwords (Argon2), secure token-based authentication (JWT), and HTTPS for all data transmission.</p>

<h2>5. Data Retention</h2>
<p>We retain your data for as long as your account is active. Attendance and payment records are retained for academy record-keeping purposes. You can delete your account at any time from the app (Settings &gt; Delete Account), which will permanently remove your account and all associated data.</p>

<h2>6. Children's Privacy</h2>
<p>Our app is used by parents/guardians to manage their children's swimming academy enrollment. Parent accounts manage athlete profiles on behalf of minors. We do not knowingly collect data directly from children under 13.</p>

<h2>7. Your Rights</h2>
<ul>
<li>Access your personal data through the app.</li>
<li>Request correction of inaccurate data by contacting administration.</li>
<li>Request deletion of your account and associated data.</li>
</ul>

<h2>8. Changes to This Policy</h2>
<p>We may update this privacy policy from time to time. Changes will be reflected on this page with an updated date.</p>

<h2>9. Contact Us</h2>
<p>If you have questions about this privacy policy, contact us at:<br>
<strong>Email:</strong> noreply@aquathletic.app</p>
</body>
</html>"""


