"""Coach endpoints — a coach sees only their own schedule and swimmers."""

from fastapi import APIRouter, Depends, HTTPException

from app.models.admin_user import AdminUser
from app.routers.deps import get_current_coach
from app.schemas.coach import CoachSession, CoachScheduleResponse
from app.services.coach_accounts import normalize_coach_name

router = APIRouter(prefix="/coach", tags=["coach"])

_DAY_ORDER = {
    "saturday": 0, "sunday": 1, "monday": 2, "tuesday": 3,
    "wednesday": 4, "thursday": 5, "friday": 6,
}


def _get_roster_source():
    from app.main import roster_source
    return roster_source


def _session_sort_key(key: tuple[str, str]):
    day_pair, time_block = key
    first_day = day_pair.split("-")[0].strip().lower() if day_pair else ""
    return (_DAY_ORDER.get(first_day, 99), day_pair, time_block)


@router.get("/schedule", response_model=CoachScheduleResponse)
async def my_schedule(coach: AdminUser = Depends(get_current_coach)):
    if not coach.assigned_branch_id or not coach.coach_name:
        raise HTTPException(status_code=403, detail="Coach account has no branch or coach name assigned")

    source = _get_roster_source()
    roster = await source.get_branch_roster(coach.assigned_branch_id)
    if not roster:
        raise HTTPException(status_code=503, detail="Branch data not available")

    coach_key = normalize_coach_name(coach.coach_name)
    grouped: dict[tuple[str, str], list[str]] = {}

    for athlete in roster.athletes:
        for slot in athlete.schedule:
            if slot.coach and normalize_coach_name(slot.coach) == coach_key:
                key = (slot.day_pair or "", slot.time_block or "")
                grouped.setdefault(key, []).append(athlete.name)

    sessions = [
        CoachSession(
            day_pair=day_pair or None,
            time_block=time_block or None,
            swimmers=sorted(names),
        )
        for (day_pair, time_block), names in sorted(grouped.items(), key=lambda item: _session_sort_key(item[0]))
    ]

    return CoachScheduleResponse(
        coach_name=coach.coach_name,
        branch_name=roster.branch_name,
        sessions=sessions,
    )
