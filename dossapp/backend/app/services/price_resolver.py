"""Resolve an athlete's bill amount from the price catalog.

Maps Excel roster fields (type, step, segment, sessions) to a canonical
program_name, then looks up the most specific matching catalog entry.
"""

import re
from decimal import Decimal
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.price_catalog import PriceCatalog


# ── Excel → Catalog mapping ──────────────────────────────────────────────

def _normalize_program_name(athlete_type: Optional[str], athlete_step: Optional[str]) -> list[str]:
    """Return candidate program names (most specific first) from Excel fields."""
    t = (athlete_type or "").strip().lower()
    s = (athlete_step or "").strip().lower()

    candidates: list[str] = []

    # Private variants
    if "private" in t and "semi" not in t:
        candidates.append("Private 1-to-1")
        candidates.append("Private Training")

    # Semi-private variants
    elif "semi" in t:
        # Extract the number (e.g., "Semi-Private.2" → "2")
        m = re.search(r"(\d)", t)
        if m:
            n = m.group(1)
            candidates.append(f"Semi-Private {n}")
            candidates.append(f"Semi-Private ({n} Students)")
        candidates.append("Semi-Private Training")

    # Elite team
    elif "elite" in t or "elite" in s:
        candidates.append("Elite Team")

    # Junior team
    elif "junior" in t or "junior" in s:
        candidates.append("Junior Team")

    # Pre-team
    elif "pre" in t or "pre" in s:
        candidates.append("Pre-Team")

    # Baby classes
    elif "baby" in t or "baby" in s:
        if "private" in t:
            candidates.append("Baby Classes - Private")
        else:
            candidates.append("Baby Classes - Group")

    # Class/group — differentiate by step
    elif t in ("class", "group", "") or "class" in t:
        # Adult
        if "adult" in s:
            candidates.append("Adult Training")
        # Level One / Beginners (Step 1)
        elif s in ("st.1", "step 1", "level 1", "l1", "1"):
            candidates.append("Level One")
            candidates.append("Step 1-6")
            candidates.append("Group Training")
        # Higher steps → Group Training (or Step 1-6 for October)
        else:
            # Steps 2-9 map to either "Group Training" or "Step 1-6"
            candidates.append("Group Training")
            candidates.append("Step 1-6")
            candidates.append("Level One")

    # Fallback: try the raw type as program name
    if athlete_type and athlete_type.strip():
        candidates.append(athlete_type.strip())

    # Ultimate fallback: try Group Training / Level One so athletes on branches
    # with flat pricing (Rehab, Madinaty) always get a bill even if their type
    # (e.g. "Pre Team", "Junior Teams") doesn't have a specific catalog entry.
    for fb in ("Group Training", "Step 1-6", "Level One"):
        if fb not in candidates:
            candidates.append(fb)

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
    """Keep sessions as-is if present, normalize formatting."""
    if not sessions:
        return None
    s = sessions.strip()
    if not s:
        return None
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

    for candidate in candidates:
        c = candidate.strip().lower()

        if (c, seg_lower, sess_lower) in catalog:
            return catalog[(c, seg_lower, sess_lower)]
        if (c, seg_lower, None) in catalog:
            return catalog[(c, seg_lower, None)]
        if (c, None, sess_lower) in catalog:
            return catalog[(c, None, sess_lower)]
        if (c, None, None) in catalog:
            return catalog[(c, None, None)]

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

import logging

logger = logging.getLogger(__name__)

_SK_ROW_MAP: list[tuple[list[str], str, Optional[str]]] = [
    # (keywords_in_row_label, program_name, segment)
    # Order: most specific first
    (["private", "1/1"], "Private 1-to-1", None),
    (["private", "1-to-1"], "Private 1-to-1", None),
    (["private", "1:1"], "Private 1-to-1", None),
    (["semi", "4"], "Semi-Private 4", None),
    (["semi", "3"], "Semi-Private 3", None),
    (["semi", "2"], "Semi-Private 2", None),
    (["semi"], "Semi-Private Training", None),
    (["elite"], "Elite Team", None),
    (["junior"], "Junior Team", None),
    (["pre-team"], "Pre-Team", None),
    (["pre team"], "Pre-Team", None),
    (["baby"], "Baby Classes - Group", None),
    (["adult"], "Adult Training", None),
    (["all"], "Group Training", None),
    (["class", "gems"], "Group Training", "Student"),
    (["class", "regular"], "Group Training", None),
    (["class", "sch"], "Group Training", "Student"),
    (["class", "outsider"], "Group Training", "Outsider"),
    (["class"], "Group Training", None),
    (["st.1"], "Level One", None),
    (["step 1"], "Level One", None),
    (["level 1"], "Level One", None),
    (["group"], "Group Training", None),
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

    # Clean up bad entries from previous syncs (non-session values, tiny prices)
    all_entries = await db.execute(
        select(PriceCatalog).where(
            PriceCatalog.branch_id == branch_id,
            PriceCatalog.is_active == True,  # noqa: E712
        )
    )
    for entry in all_entries.scalars().all():
        is_bad = False
        if entry.price < 50:
            is_bad = True
        if entry.sessions and not re.match(r"^\d+ Sessions$", entry.sessions):
            is_bad = True
        if is_bad:
            logger.info(f"  Removing bad entry: {entry.program_name}/{entry.segment}/{entry.sessions} = {entry.price}")
            await db.delete(entry)

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
