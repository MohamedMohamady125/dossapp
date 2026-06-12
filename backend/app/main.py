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
from app.routers import auth, customer, admin, webhooks
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
        for i in range(1, 8):
            file_id = getattr(settings, f"drive_file_id_branch_{i}", "")
            if file_id:
                configs.append({
                    "branch_id": i,
                    "branch_name": f"Branch {i}",
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
        except Exception as e:
            logger.error(f"Refresh/reconciliation error: {e}")

        await asyncio.sleep(settings.excel_refresh_interval_seconds)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global roster_source

    logger.info("Starting Aqua Athletic backend...")

    # Auto-create tables for SQLite dev mode
    from app.database import init_db
    await init_db()

    # Load branch configs from DB
    configs = await _load_branch_configs()
    roster_source = ExcelRosterSource(configs)

    if configs:
        await roster_source.refresh_all()
        logger.info(f"Initial Excel load complete ({len(configs)} branches)")

    # Skip background tasks in serverless (Vercel) — no long-running processes
    import os
    is_serverless = os.environ.get("VERCEL") or os.environ.get("AWS_LAMBDA_FUNCTION_NAME")

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
app.include_router(webhooks.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "aqua-athletic"}
