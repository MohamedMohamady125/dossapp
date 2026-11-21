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

    # Fins team (SK tab lists it as "Za3anf")
    elif "fins" in t or "za3anf" in t:
        candidates.append("Fins Team")

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


def missing_price_key(
    athlete_type: Optional[str], athlete_step: Optional[str], athlete_sessions: Optional[str]
) -> tuple[str, str]:
    """(program_name, sessions) a catalog entry needs for this athlete to get a bill."""
    candidates = _normalize_program_name(athlete_type, athlete_step)
    program = candidates[0] if candidates else (athlete_type or "Unknown")
    # "All Levels" is the catch-all row: a price filed under it would apply to
    # every other program too, so ask for one under the athlete's own type.
    if program == "All Levels" and athlete_type and athlete_type.strip():
        program = athlete_type.strip()
    return program, _normalize_sessions(athlete_sessions) or "8 Sessions"


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


def normalize_catalog_sessions(sessions: Optional[str]) -> Optional[str]:
    """Clean a sessions value typed by staff: '12', '12x', '12 sessions' -> '12 Sessions'."""
    if not sessions or not sessions.strip():
        return None
    s = sessions.strip()
    m = re.fullmatch(r"(\d+)\s*(x|sessions?)?", s, re.IGNORECASE)
    return f"{m.group(1)} Sessions" if m else s


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
        if (c, None, sess_lower) in catalog:
            return catalog[(c, None, sess_lower)]
        # If segment is unknown, try "student" first (most common), then "outsider"
        if seg_lower is None:
            if (c, "student", sess_lower) in catalog:
                return catalog[(c, "student", sess_lower)]
            if (c, "outsider", sess_lower) in catalog:
                return catalog[(c, "outsider", sess_lower)]

    return None


def diagnose_missing_bill(
    catalog: CatalogLookup,
    athlete_type: Optional[str],
    athlete_step: Optional[str],
    athlete_segment: Optional[str],
    athlete_sessions: Optional[str],
) -> str:
    """Return a human-readable explanation of why a bill can't be calculated."""
    missing = []
    if not athlete_type or not athlete_type.strip():
        missing.append("Type")
    if not catalog:
        return "No price list loaded for this branch"
    if missing:
        return f"Missing in Excel: {', '.join(missing)}"

    # Type exists but no catalog match — explain what was tried
    candidates = _normalize_program_name(athlete_type, athlete_step)
    sessions = _normalize_sessions(athlete_sessions)
    sess_lower = sessions.lower() if sessions else "8 sessions"

    # Check if ANY entry exists for this program
    candidate_names = [c.strip().lower() for c in candidates]
    catalog_programs = set(k[0] for k in catalog.keys())
    matched_program = None
    for c in candidate_names:
        if c in catalog_programs:
            matched_program = c
            break

    if not matched_program:
        return f"No price for type \"{athlete_type}\" in the price list"

    # Program exists but sessions don't match
    available_sessions = sorted(set(
        k[2] for k in catalog.keys()
        if k[0] == matched_program and k[2]
    ))
    if available_sessions:
        return f"No price for {athlete_type} at {sess_lower} (available: {', '.join(available_sessions)})"

    return f"No matching price for type \"{athlete_type}\""


async def resolve_price(
    db: AsyncSession,
    branch_id: int,
    athlete_type: Optional[str],
    athlete_step: Optional[str],
    athlete_segment: Optional[str],
    athlete_sessions: Optional[str],
    athlete_number: Optional[int] = None,
) -> Optional[Decimal]:
    """Look up the catalog price for an athlete. Checks bill overrides first."""
    # Check for admin-set bill override
    if athlete_number is not None:
        from app.models.bill_override import BillOverride
        result = await db.execute(
            select(BillOverride.amount).where(
                BillOverride.branch_id == branch_id,
                BillOverride.athlete_number == athlete_number,
            )
        )
        override = result.scalar_one_or_none()
        if override is not None:
            return override

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
    (["za3anf", "6"], "Fins Team 6D", None),
    (["fins", "6"], "Fins Team 6D", None),
    (["za3anf"], "Fins Team", None),
    (["fins"], "Fins Team", None),
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


def sk_price_entries(price_matrix: dict) -> dict[tuple, Decimal]:
    """Turn the parsed SK tab into {(program_name, segment, sessions): price}."""
    entries: dict[tuple, Decimal] = {}
    for row_label, prices in (price_matrix or {}).items():
        program_name, segment = _map_sk_row_to_program(row_label)
        for header, price_str in prices.items():
            sessions = _normalize_sk_sessions(header)
            if not sessions:
                continue  # not a session column (times, coach names, etc.)
            m = re.match(r"(\d+(?:\.\d+)?)", str(price_str))
            if not m:
                continue
            price = Decimal(m.group(1))
            if price < 50:
                continue  # unrealistic (likely a time float like 4.15)
            entries[(program_name, segment, sessions)] = price
    return entries


async def sync_price_matrix_to_catalog(
    db: AsyncSession, branch_id: int, price_matrix: dict
) -> int:
    """Make the price catalog agree with the SK tab, which is the source of truth.

    - Every price in the SK tab is upserted.
    - A catalog entry for the same program + sessions under a segment the SK
      tab does not define is removed, because the more specific entry would
      otherwise shadow the SK price.
    - Entries the SK tab says nothing about (prices staff assigned from the
      Missing page, e.g. "Junior Team / 12 Sessions") are left untouched.

    Returns the number of catalog rows added, changed or removed.
    """
    wanted = sk_price_entries(price_matrix)
    if not wanted:
        return 0

    # Several workers refresh the same sheet at once; serialise so they don't
    # insert the same row twice (NULL segments defeat the unique constraint).
    if db.bind is not None and db.bind.dialect.name == "postgresql":
        from sqlalchemy import text
        await db.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": 7340000 + branch_id})

    result = await db.execute(select(PriceCatalog).where(PriceCatalog.branch_id == branch_id))
    existing = result.scalars().all()

    def norm(v: Optional[str]) -> Optional[str]:
        return v.strip().lower() if v and v.strip() else None

    wanted_keys = {(norm(p), norm(seg), norm(sess)) for (p, seg, sess) in wanted}
    sk_slots = {(norm(p), norm(sess)) for (p, _, sess) in wanted}

    changed = 0
    by_key: dict[tuple, PriceCatalog] = {}
    for e in existing:
        key = (norm(e.program_name), norm(e.segment), norm(e.sessions))
        if key in by_key or ((key[0], key[2]) in sk_slots and key not in wanted_keys):
            # duplicate row, or one that would shadow the SK price
            await db.delete(e)
            changed += 1
            logger.info(f"  Removed price superseded by SK tab: {e.program_name}/{e.segment}/{e.sessions}")
        else:
            by_key[key] = e

    for (program_name, segment, sessions), price in wanted.items():
        e = by_key.get((norm(program_name), norm(segment), norm(sessions)))
        if e is None:
            db.add(PriceCatalog(
                branch_id=branch_id, program_name=program_name, segment=segment,
                sessions=sessions, price=price, is_active=True,
            ))
            changed += 1
            logger.info(f"  New price from SK tab: {program_name}/{segment}/{sessions} = {price}")
        elif e.price != price or not e.is_active:
            logger.info(f"  Price updated from SK tab: {program_name}/{segment}/{sessions} {e.price} -> {price}")
            e.price = price
            e.is_active = True
            changed += 1

    await db.commit()
    if changed:
        logger.info(f"Price catalog sync: {changed} changes for branch {branch_id}")
    return changed
