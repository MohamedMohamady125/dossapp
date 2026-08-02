"""Resolve an athlete's bill amount from the price catalog.

Maps Excel roster fields (type, step, segment, sessions) to a canonical
program_name, then looks up the most specific matching catalog entry.

SK Tab price rows → catalog program names:
  "Class (Regular)"  → "Class"          segment=None
  "Class (GEMS)"     → "Class"          segment="Student"
  "Private 1:1"      → "Private 1-to-1" segment=None
  "Semi Priv 1:2"    → "Semi-Private 2" segment=None
  "Semi Priv 1:3"    → "Semi-Private 3" segment=None
  "ALL"              → "All Levels"     segment=None   (catch-all for teams/Pre Team)
  "Junior Teams"     → "Junior Team"    segment=None
  "Elite Team"       → "Elite Team"     segment=None
  "st.1"             → "Step 1"         segment=None

Roster athlete types → candidate program names:
  Type="Class"               → ["Class", "Step 1", "All Levels"]
  Type="Private.1"           → ["Private 1-to-1", "All Levels"]
  Type="Private.2"/"Semi"    → ["Semi-Private 2", "Semi-Private 3", "All Levels"]
  Type="Pre Team"            → ["All Levels", "Junior Team"]
  Type="Junior Team"         → ["Junior Team", "All Levels"]
  Type="Elite Team"          → ["Elite Team", "All Levels"]
"""

import re
import logging
from decimal import Decimal
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.price_catalog import PriceCatalog

logger = logging.getLogger(__name__)


# ── Excel → Catalog mapping ──────────────────────────────────────────────

def _normalize_program_name(athlete_type: Optional[str], athlete_step: Optional[str]) -> list[str]:
    """Return candidate program names (most specific first) from Excel fields.

    Must match program names produced by _map_sk_row_to_program().
    """
    t = (athlete_type or "").strip().lower()
    s = (athlete_step or "").strip().lower()

    candidates: list[str] = []

    # Private 1-to-1 (Type="Private.1", "Private 1", etc.)
    if "private" in t and "semi" not in t:
        candidates.append("Private 1-to-1")

    # Semi-private (Type="Semi Private.2", "Semi Priv 1:2", etc.)
    elif "semi" in t:
        m = re.search(r"(\d)", t)
        if m:
            candidates.append(f"Semi-Private {m.group(1)}")
        # Try both sizes as fallback
        candidates.append("Semi-Private 2")
        candidates.append("Semi-Private 3")

    # Elite team
    elif "elite" in t or "elite" in s:
        candidates.append("Elite Team")

    # Junior team (Type or Step contains "Junior")
    elif "junior" in t or "junior" in s:
        candidates.append("Junior Team")

    # Pre-team → uses "All Levels" (same pricing as Junior Teams in SK tab)
    elif "pre" in t or "pre" in s:
        candidates.append("All Levels")
        candidates.append("Junior Team")

    # Baby classes
    elif "baby" in t or "baby" in s:
        candidates.append("Baby Classes")

    # Class/group (Type="Class")
    elif t in ("class", "group", "") or "class" in t:
        # Step 1 has its own higher pricing in SK tab ("st.1" row)
        if s in ("st.1", "step 1", "level 1", "l1", "1"):
            candidates.append("Step 1")
        candidates.append("Class")

    # Fallback: try the raw type as-is
    if athlete_type and athlete_type.strip():
        raw = athlete_type.strip()
        if raw not in candidates:
            candidates.append(raw)

    # Ultimate catch-all: "All Levels" (from SK "ALL" row)
    if "All Levels" not in candidates:
        candidates.append("All Levels")

    return candidates


def _normalize_segment(segment: Optional[str]) -> Optional[str]:
    """Map Excel segment values to catalog segment values."""
    if not segment:
        return None
    seg = segment.strip().lower()
    if seg in ("gems sch.", "gems", "member", "student"):
        return "Student"
    if seg in ("outsider", "non member", "outside"):
        return "Outsider"
    return None


def _normalize_sessions(sessions: Optional[str]) -> Optional[str]:
    """Normalize sessions to 'N Sessions' format to match catalog entries."""
    if not sessions:
        return None
    s = sessions.strip()
    if not s:
        return None
    # Extract the number and normalize to "N Sessions"
    m = re.match(r"^(\d+)", s)
    if m:
        return f"{m.group(1)} Sessions"
    return s


# ── Catalog lookup ────────────────────────────────────────────────────────

# Type alias for pre-loaded catalog lookup dict
CatalogLookup = dict[tuple, Decimal]


async def load_branch_catalog(db: AsyncSession, branch_id: int) -> CatalogLookup:
    """Pre-load all active catalog entries for a branch into a lookup dict.

    Use this when resolving prices for many athletes to avoid repeated DB queries.
    """
    result = await db.execute(
        select(PriceCatalog).where(
            PriceCatalog.branch_id == branch_id,
            PriceCatalog.is_active == True,  # noqa: E712
        )
    )
    entries = result.scalars().all()
    lookup: CatalogLookup = {}
    for e in entries:
        key = (
            e.program_name.strip().lower(),
            e.segment.strip().lower() if e.segment else None,
            e.sessions.strip().lower() if e.sessions else None,
        )
        lookup[key] = e.price
    return lookup


def resolve_price_from_catalog(
    catalog: CatalogLookup,
    athlete_type: Optional[str],
    athlete_step: Optional[str],
    athlete_segment: Optional[str],
    athlete_sessions: Optional[str],
) -> Optional[Decimal]:
    """Pure function: resolve price from a pre-loaded catalog. No DB queries."""

    candidates = _normalize_program_name(athlete_type, athlete_step)
    if not candidates:
        return None

    segment = _normalize_segment(athlete_segment)
    sessions = _normalize_sessions(athlete_sessions)

    if not catalog:
        return None

    seg_lower = segment.lower() if segment else None
    sess_lower = sessions.lower() if sessions else None

    # If athlete has no sessions specified, default to "8 Sessions" (standard monthly)
    if sess_lower is None:
        sess_lower = "8 sessions"

    for candidate in candidates:
        c = candidate.strip().lower()

        # Exact match: program + segment + sessions
        if (c, seg_lower, sess_lower) in catalog:
            return catalog[(c, seg_lower, sess_lower)]
        # Try without segment (e.g., no GEMS/Outsider distinction)
        if seg_lower and (c, None, sess_lower) in catalog:
            return catalog[(c, None, sess_lower)]

    return None


async def resolve_price(
    db: AsyncSession,
    branch_id: int,
    athlete_type: Optional[str],
    athlete_step: Optional[str],
    athlete_segment: Optional[str],
    athlete_sessions: Optional[str],
) -> Optional[Decimal]:
    """Look up the catalog price for an athlete. Convenience wrapper for single lookups."""
    catalog = await load_branch_catalog(db, branch_id)
    return resolve_price_from_catalog(catalog, athlete_type, athlete_step, athlete_segment, athlete_sessions)


# ── SK tab → Price Catalog sync ─────────────────────────────────────────

_SK_ROW_MAP: list[tuple[list[str], str, Optional[str]]] = [
    # (keywords_in_row_label, program_name, segment)
    # Order: most specific first — must match _normalize_program_name() output
    #
    # Real SK tab rows from Rehab branch:
    #   "Class (Regular)" → Class / None
    #   "Class (GEMS)"    → Class / Student
    #   "Private 1:1"     → Private 1-to-1 / None
    #   "Semi Priv 1:2"   → Semi-Private 2 / None
    #   "Semi Priv 1:3"   → Semi-Private 3 / None
    #   "ALL"             → All Levels / None  (catch-all, must NOT collide with Class)
    #   "Junior Teams"    → Junior Team / None
    #   "Elite Team"      → Elite Team / None
    #   "st.1"            → Step 1 / None
    (["private", "1/1"], "Private 1-to-1", None),
    (["private", "1-to-1"], "Private 1-to-1", None),
    (["private", "1:1"], "Private 1-to-1", None),
    (["semi", "1:4"], "Semi-Private 4", None),
    (["semi", "1:3"], "Semi-Private 3", None),
    (["semi", "1:2"], "Semi-Private 2", None),
    (["semi", "4"], "Semi-Private 4", None),
    (["semi", "3"], "Semi-Private 3", None),
    (["semi", "2"], "Semi-Private 2", None),
    (["semi"], "Semi-Private 2", None),
    (["elite"], "Elite Team", None),
    (["junior"], "Junior Team", None),
    (["pre-team"], "All Levels", None),
    (["pre team"], "All Levels", None),
    (["baby"], "Baby Classes", None),
    (["adult"], "Adult Training", None),
    (["class", "gems"], "Class", "Student"),
    (["class", "sch"], "Class", "Student"),
    (["class", "outsider"], "Class", "Outsider"),
    (["class", "regular"], "Class", None),
    (["class"], "Class", None),
    (["st.1"], "Step 1", None),
    (["step 1"], "Step 1", None),
    (["level 1"], "Step 1", None),
    (["all"], "All Levels", None),
    (["group"], "Class", None),
]


def _map_sk_row_to_program(row_label: str) -> tuple[str, Optional[str]]:
    """Map an SK tab row label to (program_name, segment).

    Returns the raw label as program_name if no mapping matches.
    """
    label = row_label.lower().strip()
    for keywords, program, segment in _SK_ROW_MAP:
        if all(kw in label for kw in keywords):
            return program, segment
    # Fallback: use the raw label as program name
    return row_label.strip(), None


def _normalize_sk_sessions(header: str) -> Optional[str]:
    """Map SK tab column header like '8 x' or '8x' to '8 Sessions'."""
    m = re.match(r"(\d+)\s*x", header.strip(), re.IGNORECASE)
    if m:
        return f"{m.group(1)} Sessions"
    # Try plain number
    m = re.match(r"^(\d+)$", header.strip())
    if m:
        return f"{m.group(1)} Sessions"
    # Unrecognized header — not a session column, skip it
    return None


async def sync_price_matrix_to_catalog(
    db: AsyncSession, branch_id: int, price_matrix: dict
) -> int:
    """Upsert SK tab price_matrix entries into the price_catalog table.

    Returns the number of entries upserted.
    """
    if not price_matrix:
        return 0

    # Wipe all existing auto-synced entries for this branch and rebuild fresh.
    # This prevents stale data from old program-name mappings lingering.
    old_entries = await db.execute(
        select(PriceCatalog).where(PriceCatalog.branch_id == branch_id)
    )
    for entry in old_entries.scalars().all():
        await db.delete(entry)
    await db.flush()

    count = 0
    for row_label, prices in price_matrix.items():
        program_name, segment = _map_sk_row_to_program(row_label)

        for header, price_str in prices.items():
            sessions = _normalize_sk_sessions(header)
            if not sessions:
                continue  # Skip non-session columns (times, coach names, etc.)
            # Extract numeric price
            m = re.match(r"(\d+(?:\.\d+)?)", str(price_str))
            if not m:
                continue
            price = Decimal(m.group(1))
            if price < 50:
                continue  # Skip unrealistic prices (likely time floats like 4.15)

            # Upsert: check if entry exists
            result = await db.execute(
                select(PriceCatalog).where(
                    PriceCatalog.branch_id == branch_id,
                    PriceCatalog.program_name == program_name,
                    PriceCatalog.segment == segment,
                    PriceCatalog.sessions == sessions,
                )
            )
            existing = result.scalar_one_or_none()

            if existing:
                if existing.price != price:
                    existing.price = price
                    existing.is_active = True
                    count += 1
                    logger.info(f"  Updated price: {program_name}/{segment}/{sessions} → {price}")
            else:
                entry = PriceCatalog(
                    branch_id=branch_id,
                    program_name=program_name,
                    segment=segment,
                    sessions=sessions,
                    price=price,
                    is_active=True,
                )
                db.add(entry)
                count += 1
                logger.info(f"  New price: {program_name}/{segment}/{sessions} → {price}")

    await db.commit()
    logger.info(f"Price catalog sync: {count} entries upserted for branch {branch_id}")
    return count
