"""Receipt PDF generation using HTML template + weasyprint."""

import io
import os
from datetime import datetime, timezone
from pathlib import Path

from weasyprint import HTML


_TEMPLATE_DIR = Path(__file__).parent
_TEMPLATE_PATH = _TEMPLATE_DIR / "receipt_template.html"
_LOGO_PATH = _TEMPLATE_DIR / "logo.b64"

# Cache template + logo at module level
_template_cache: str | None = None
_logo_cache: str | None = None


def _get_template() -> str:
    global _template_cache
    if _template_cache is None:
        _template_cache = _TEMPLATE_PATH.read_text(encoding="utf-8")
    return _template_cache


def _get_logo_base64() -> str:
    global _logo_cache
    if _logo_cache is None:
        if _LOGO_PATH.exists():
            _logo_cache = _LOGO_PATH.read_text(encoding="utf-8").strip()
        else:
            _logo_cache = ""
    return _logo_cache


# Arabic month names
_AR_MONTHS = {
    1: "يناير", 2: "فبراير", 3: "مارس", 4: "أبريل",
    5: "مايو", 6: "يونيو", 7: "يوليو", 8: "أغسطس",
    9: "سبتمبر", 10: "أكتوبر", 11: "نوفمبر", 12: "ديسمبر",
}


def _format_period_arabic(period: str) -> str:
    """Convert '2026-08' to 'أغسطس 2026'."""
    try:
        parts = period.split("-")
        year = parts[0]
        month = int(parts[1])
        return f"{_AR_MONTHS.get(month, period)} {year}"
    except (IndexError, ValueError):
        return period


def _format_date_arabic(dt: datetime) -> str:
    """Format datetime as 'DD month YYYY'."""
    month_name = _AR_MONTHS.get(dt.month, str(dt.month))
    return f"{dt.day} {month_name} {dt.year}"


def _channel_arabic(channel: str) -> str:
    """Translate payment channel to Arabic."""
    mapping = {
        "online": "دفع إلكتروني عبر EasyKash",
        "cash": "نقدي في الفرع",
        "card": "بطاقة في الفرع",
        "manual": "يدوي",
    }
    return mapping.get(channel.lower(), channel)


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
    """Generate a branded Arabic receipt PDF. Returns PDF bytes."""
    if issued_at is None:
        issued_at = datetime.now(timezone.utc)

    template = _get_template()
    logo_b64 = _get_logo_base64()

    # Build line item details
    detail_parts = []
    if level:
        detail_parts.append(f"المستوى: {level}")
    if athlete_type:
        detail_parts.append(f"النوع: {athlete_type}")
    line_detail = " · ".join(detail_parts) if detail_parts else ""

    # Sessions count from amount context (not available directly, use dash)
    sessions = "—"

    # Channel note
    channel_note = _channel_arabic(payment_channel)
    if paymob_transaction_id:
        channel_note += f" — معرف العملية: {paymob_transaction_id}"

    # Contact line
    contact_line = "aquathletic.com"

    html_content = template.format(
        logo_base64=logo_b64,
        receipt_number=receipt_number,
        issued_at=_format_date_arabic(issued_at),
        swimmer_name=athlete_name,
        branch_name=branch_name,
        period=_format_period_arabic(period),
        phone=phone or "—",
        line_title=f"رسوم تدريب — {_format_period_arabic(period)}",
        line_detail=line_detail,
        sessions=sessions,
        amount_line=f"{amount_paid} ج.م",
        amount_total=f"{amount_paid} ج.م",
        channel_note=channel_note,
        contact_line=contact_line,
    )

    pdf_bytes = HTML(string=html_content).write_pdf()
    return pdf_bytes
