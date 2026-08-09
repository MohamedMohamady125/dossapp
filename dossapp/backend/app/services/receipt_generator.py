"""Receipt PDF generation using weasyprint."""

import io
import logging
from datetime import datetime, timezone, timedelta
from pathlib import Path

logger = logging.getLogger(__name__)

_DIR = Path(__file__).parent
_TEMPLATE: str | None = None
_LOGO_B64: str | None = None


def _get_template() -> str:
    global _TEMPLATE
    if _TEMPLATE is None:
        _TEMPLATE = (_DIR / "receipt_template.html").read_text(encoding="utf-8")
    return _TEMPLATE


def _get_logo() -> str:
    global _LOGO_B64
    if _LOGO_B64 is None:
        _LOGO_B64 = (_DIR / "logo.b64").read_text(encoding="utf-8").strip()
    return _LOGO_B64


_MONTHS_EN = {
    1: "January", 2: "February", 3: "March", 4: "April",
    5: "May", 6: "June", 7: "July", 8: "August",
    9: "September", 10: "October", 11: "November", 12: "December",
}


def _format_period(period: str) -> str:
    """Convert '2026-08' to 'August 2026'."""
    try:
        parts = period.split("-")
        month = _MONTHS_EN.get(int(parts[1]), period)
        return f"{month} {parts[0]}"
    except (IndexError, ValueError):
        return period


def _format_date(dt: datetime) -> str:
    month = _MONTHS_EN.get(dt.month, str(dt.month))
    hour = dt.hour % 12 or 12
    ampm = "PM" if dt.hour >= 12 else "AM"
    return f"{dt.day} {month} {dt.year} - {hour}:{dt.minute:02d} {ampm}"


def _clean_amount(amount: str) -> str:
    """Remove trailing zeros: '1000.00' -> '1000', '1250.50' -> '1250.5'."""
    if "." in amount:
        return amount.rstrip("0").rstrip(".")
    return amount


def _channel_note(channel: str, txn_id: str | None) -> str:
    ch = channel.lower()
    if ch == "online":
        txn = txn_id or ""
        return f"Paid online via card or wallet — Transaction ID: {txn}."
    elif ch == "card":
        return "Paid by card at the branch reception."
    else:
        return "Cash payment received at the branch reception."


def generate_receipt_pdf(
    receipt_number: str,
    athlete_name: str,
    athlete_number: int,
    branch_name: str,
    level: str | None,
    athlete_type: str | None,
    phone: str | None,
    period: str,
    amount_paid: str,
    payment_channel: str,
    paymob_transaction_id: str | None = None,
    issued_at: datetime | None = None,
) -> bytes:
    """Generate a branded English receipt PDF. Returns PDF bytes."""
    if issued_at is None:
        # Egypt is UTC+2 (EET); no DST since 2014
        _EET = timezone(timedelta(hours=2))
        issued_at = datetime.now(_EET)

    amount_paid = _clean_amount(amount_paid)
    amount_display = f"{amount_paid} EGP"
    period_display = _format_period(period)

    # Build detail line
    detail_parts = []
    if athlete_type:
        detail_parts.append(athlete_type)
    if level:
        detail_parts.append(level)
    detail_parts.append(branch_name)
    line_detail = " · ".join(detail_parts)

    html = _get_template().format(
        logo_b64=_get_logo(),
        receipt_number=receipt_number,
        issued_at=_format_date(issued_at),
        swimmer_name=athlete_name,
        branch_name=branch_name,
        period=period_display,
        phone=phone or "",
        sessions="",
        line_title=f"Monthly Training Fees — {period_display}",
        line_detail=line_detail,
        amount_line=amount_display,
        amount_total=amount_display,
        channel_note=_channel_note(payment_channel, paymob_transaction_id),
        contact_line="",
    )

    from weasyprint import HTML
    buffer = io.BytesIO()
    HTML(string=html).write_pdf(buffer)
    return buffer.getvalue()
