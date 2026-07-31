"""ExcelRosterSource — concrete RosterSource backed by Google Drive Excel files.

Implements caching + refresh-on-change per branch.
"""

import asyncio
import logging
import os
from datetime import datetime, timezone
from typing import Optional

from app.services.roster_source import RosterSource, BranchRoster
from app.services.excel_parser import parse_workbook
from app.services.drive_reader import download_file, get_file_modified_time

logger = logging.getLogger(__name__)


class ExcelRosterSource(RosterSource):
    def __init__(self, branch_configs: list[dict]):
        """
        branch_configs: list of {branch_id, branch_name, drive_file_id}
        """
        self._configs = {c["branch_id"]: c for c in branch_configs}
        self._cache: dict[int, BranchRoster] = {}
        self._last_modified: dict[int, Optional[str]] = {}
        self._last_errors: dict[int, list[str]] = {}
        self._lock = asyncio.Lock()
        self._initial_load_done = False

    async def _ensure_loaded(self):
        """Lazy-load data on first access (needed for serverless cold starts).

        Only loads Excel data — reconciliation, coach sync, and push triggers
        run exclusively via cron endpoints to keep cold-start latency low.
        """
        if not self._initial_load_done and self._configs:
            self._initial_load_done = True
            await self.refresh_all()

    async def _run_reconciliation(self):
        """Sync Excel payment data to the database."""
        from app.database import async_session
        from app.services.reconciliation import reconcile_branch

        for branch_id, roster in self._cache.items():
            try:
                async with async_session() as db:
                    count = await reconcile_branch(roster, db)
                    if count > 0:
                        logger.info(f"Reconciled {count} cash payments for branch {branch_id}")
            except Exception as e:
                logger.error(f"Reconciliation error for branch {branch_id}: {e}")

    async def _run_coach_sync(self):
        """Auto-create coach login accounts for coaches found in the rosters."""
        from app.database import async_session
        from app.services.coach_accounts import sync_coach_accounts

        for branch_id, roster in self._cache.items():
            try:
                async with async_session() as db:
                    count = await sync_coach_accounts(roster, db)
                    if count > 0:
                        logger.info(f"Created {count} coach accounts for branch {branch_id}")
            except Exception as e:
                logger.error(f"Coach sync error for branch {branch_id}: {e}")

    async def _run_push_triggers(self):
        """Detect schedule changes / missed sessions and send notifications."""
        from app.database import async_session
        from app.services.push_triggers import run_roster_triggers

        for branch_id, roster in self._cache.items():
            try:
                async with async_session() as db:
                    counts = await run_roster_triggers(roster, db)
                    if counts["schedule"] or counts["missed"]:
                        logger.info(f"Push triggers branch {branch_id}: {counts}")
            except Exception as e:
                logger.error(f"Push trigger error for branch {branch_id}: {e}")

    async def get_branch_roster(self, branch_id: int) -> Optional[BranchRoster]:
        await self._ensure_loaded()
        return self._cache.get(branch_id)

    async def get_all_rosters(self) -> dict[int, BranchRoster]:
        await self._ensure_loaded()
        return dict(self._cache)

    async def refresh_branch(self, branch_id: int) -> bool:
        config = self._configs.get(branch_id)
        if not config:
            logger.warning(f"No config for branch {branch_id}")
            return False

        # Support local file path for testing (no Google Drive needed)
        local_path = config.get("local_file_path")
        if local_path:
            return await self._refresh_from_local(branch_id, config, local_path)

        drive_file_id = config.get("drive_file_id")
        if not drive_file_id:
            logger.warning(f"No drive_file_id for branch {branch_id}")
            return False

        try:
            # Check if file has changed
            current_modified = await asyncio.to_thread(get_file_modified_time, drive_file_id)
            if current_modified and current_modified == self._last_modified.get(branch_id):
                return False  # No change

            # Download and parse
            tmp_path = await asyncio.to_thread(download_file, drive_file_id)
            if not tmp_path:
                logger.error(f"Failed to download file for branch {branch_id} (drive_file_id={drive_file_id})")
                self._last_errors[branch_id] = [f"Download failed at {datetime.now(timezone.utc).isoformat()}"]
                return False

            try:
                athletes, coaches, price_matrix, errors = await asyncio.to_thread(
                    parse_workbook, tmp_path, config["branch_name"], branch_id
                )

                roster = BranchRoster(
                    branch_id=branch_id,
                    branch_name=config["branch_name"],
                    athletes=athletes,
                    coaches=coaches,
                    price_matrix=price_matrix,
                    parse_errors=errors,
                    last_modified=current_modified,
                    last_refreshed=datetime.now(timezone.utc).isoformat(),
                    period=datetime.now().strftime("%Y-%m"),  # Tier 3: stamp with current period
                )

                async with self._lock:
                    self._cache[branch_id] = roster
                    self._last_modified[branch_id] = current_modified
                    self._last_errors[branch_id] = errors

                if errors:
                    logger.warning(f"Branch {branch_id} parsed with {len(errors)} warnings: {errors[:3]}")

                logger.info(f"Branch {branch_id}: loaded {len(athletes)} athletes")
                return True

            finally:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass

        except Exception as e:
            logger.error(f"Failed to refresh branch {branch_id}: {e}")
            self._last_errors[branch_id] = [f"Refresh error: {e}"]
            # Keep serving previous good cache
            return False

    async def _refresh_from_local(self, branch_id: int, config: dict, local_path: str) -> bool:
        """Load roster from a local Excel file (for testing without Google Drive)."""
        import os
        if not os.path.exists(local_path):
            logger.warning(f"Local file not found: {local_path}")
            return False

        # Check file modification time
        mtime = str(os.path.getmtime(local_path))
        if mtime == self._last_modified.get(branch_id):
            return False

        try:
            athletes, coaches, price_matrix, errors = await asyncio.to_thread(
                parse_workbook, local_path, config["branch_name"], branch_id
            )
            roster = BranchRoster(
                branch_id=branch_id,
                branch_name=config["branch_name"],
                athletes=athletes,
                coaches=coaches,
                price_matrix=price_matrix,
                parse_errors=errors,
                last_modified=mtime,
                last_refreshed=datetime.now(timezone.utc).isoformat(),
                period=datetime.now().strftime("%Y-%m"),
            )
            async with self._lock:
                self._cache[branch_id] = roster
                self._last_modified[branch_id] = mtime
                self._last_errors[branch_id] = errors

            logger.info(f"Branch {branch_id} (local): loaded {len(athletes)} athletes")
            return True
        except Exception as e:
            logger.error(f"Failed to parse local file for branch {branch_id}: {e}")
            self._last_errors[branch_id] = [f"Parse error: {e}"]
            return False

    async def refresh_all(self, force: bool = False) -> dict[int, bool]:
        if force:
            # Clear cached modification times to force re-download + re-parse
            self._last_modified.clear()
        # Download and parse all branches in parallel for faster cold starts
        tasks = {bid: self.refresh_branch(bid) for bid in self._configs}
        gathered = await asyncio.gather(*tasks.values(), return_exceptions=True)
        results = {}
        for bid, result in zip(tasks.keys(), gathered):
            if isinstance(result, Exception):
                logger.error(f"Branch {bid} refresh failed: {result}")
                results[bid] = False
            else:
                results[bid] = result
        return results

    def update_config(self, branch_id: int, config: dict):
        """Add or update a branch config at runtime (no restart needed)."""
        self._configs[branch_id] = config

    def remove_config(self, branch_id: int):
        """Remove a branch config and its cached data."""
        self._configs.pop(branch_id, None)
        self._cache.pop(branch_id, None)
        self._last_modified.pop(branch_id, None)
        self._last_errors.pop(branch_id, None)

    def get_health(self) -> dict:
        health = {}
        for branch_id, config in self._configs.items():
            roster = self._cache.get(branch_id)
            health[branch_id] = {
                "branch_name": config["branch_name"],
                "loaded": roster is not None,
                "athlete_count": len(roster.athletes) if roster else 0,
                "last_modified": roster.last_modified if roster else None,
                "last_refreshed": roster.last_refreshed if roster else None,
                "errors": self._last_errors.get(branch_id, []),
            }
        return health
