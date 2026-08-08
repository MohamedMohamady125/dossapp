"""Receipt PDF generation using weasyprint with Arabic RTL template."""

import io
import logging
from datetime import datetime, timezone
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

_MONTHS_AR = {
    1: "يناير", 2: "فبراير", 3: "مارس", 4: "أبريل",
    5: "مايو", 6: "يونيو", 7: "يوليو", 8: "أغسطس",
    9: "سبتمبر", 10: "أكتوبر", 11: "نوفمبر", 12: "ديسمبر",
}

_EASTERN_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")


def _to_eastern(s: str) -> str:
    return s.translate(_EASTERN_DIGITS)


def _format_period_ar(period: str) -> str:
    """Convert '2026-08' to 'أغسطس ٢٠٢٦'."""
    try:
        parts = period.split("-")
        month = _MONTHS_AR.get(int(parts[1]), period)
        year = _to_eastern(parts[0])
        return f"{month} {year}"
    except (IndexError, ValueError):
        return period


def _format_date_ar(dt: datetime) -> str:
    day = _to_eastern(str(dt.day))
    month = _MONTHS_AR.get(dt.month, str(dt.month))
    year = _to_eastern(str(dt.year))
    hour = dt.hour % 12 or 12
    minute = _to_eastern(f"{dt.minute:02d}")
    hour_str = _to_eastern(str(hour))
    ampm = "م" if dt.hour >= 12 else "ص"
    return f"{day} {month} {year} - {hour_str}:{minute} {ampm}"


def _clean_amount(amount: str) -> str:
    """Remove trailing zeros: '1000.00' -> '1000', '1250.50' -> '1250.5'."""
    if "." in amount:
        return amount.rstrip("0").rstrip(".")
    return amount


def _channel_note(channel: str, txn_id: str | None) -> str:
    ch = channel.lower()
    if ch == "online":
        txn = txn_id or ""
        return f"تم السداد إلكترونيًا بالبطاقة أو المحفظة — رقم العملية {txn}."
    elif ch == "card":
        return "تم الدفع بالبطاقة في مكتب استقبال الفرع."
    else:
        return "تم استلام المبلغ نقدًا بمكتب استقبال الفرع."


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

    amount_paid = _clean_amount(amount_paid)
    amount_ar = _to_eastern(amount_paid) + " جنيه"
    period_ar = _format_period_ar(period)

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
        issued_at=_format_date_ar(issued_at),
        swimmer_name=athlete_name,
        branch_name=branch_name,
        period=period_ar,
        phone=phone or "",
        sessions="",
        line_title=f"رسوم التدريب الشهرية — {period_ar}",
        line_detail=line_detail,
        amount_line=amount_ar,
        amount_total=amount_ar,
        channel_note=_channel_note(payment_channel, paymob_transaction_id),
        contact_line="aquathletic.eg",
    )

    from weasyprint import HTML
    buffer = io.BytesIO()
    HTML(string=html).write_pdf(buffer)
    return buffer.getvalue()
