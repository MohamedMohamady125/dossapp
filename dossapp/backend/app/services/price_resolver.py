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
