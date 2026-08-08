"""Receipt PDF generation using xhtml2pdf (pure Python, no system deps)."""

import io
from datetime import datetime, timezone

from xhtml2pdf import pisa


# Arabic month names
_AR_MONTHS = {
    1: "يناير", 2: "فبراير", 3: "مارس", 4: "أبريل",
    5: "مايو", 6: "يونيو", 7: "يوليو", 8: "أغسطس",
    9: "سبتمبر", 10: "أكتوبر", 11: "نوفمبر", 12: "ديسمبر",
}


def _format_period(period: str) -> str:
    """Convert '2026-08' to 'أغسطس 2026'."""
    try:
        parts = period.split("-")
        return f"{_AR_MONTHS.get(int(parts[1]), period)} {parts[0]}"
    except (IndexError, ValueError):
        return period


def _format_date(dt: datetime) -> str:
    return f"{dt.day} {_AR_MONTHS.get(dt.month, str(dt.month))} {dt.year}"


def _channel_label(channel: str) -> str:
    mapping = {
        "online": "Online — EasyKash",
        "cash": "Cash",
        "card": "Card",
        "manual": "Manual",
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
    """Generate a branded receipt PDF. Returns PDF bytes."""
    if issued_at is None:
        issued_at = datetime.now(timezone.utc)

    detail_parts = []
    if level:
        detail_parts.append(f"Level: {level}")
    if athlete_type:
        detail_parts.append(f"Type: {athlete_type}")
    detail_line = " · ".join(detail_parts) if detail_parts else ""

    channel = _channel_label(payment_channel)
    txn_line = f'<tr><td class="label">Transaction ID</td><td class="value mono">{paymob_transaction_id}</td></tr>' if paymob_transaction_id else ""

    html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  @page {{
    size: A4;
    margin: 20mm 25mm;
  }}
  body {{
    font-family: Helvetica, Arial, sans-serif;
    color: #1E293B;
    font-size: 11pt;
    line-height: 1.5;
    margin: 0;
    padding: 0;
  }}
  .header {{
    text-align: center;
    border-bottom: 3px solid #F9A825;
    padding-bottom: 12px;
    margin-bottom: 20px;
  }}
  .brand {{
    font-size: 28pt;
    font-weight: bold;
    color: #0D1B2A;
    letter-spacing: 2px;
    margin: 0;
  }}
  .tagline {{
    font-size: 10pt;
    color: #1565C0;
    font-style: italic;
    margin: 2px 0;
  }}
  .branch {{
    font-size: 12pt;
    color: #64748B;
    font-weight: bold;
    margin: 4px 0 0;
  }}
  .receipt-title {{
    text-align: center;
    font-size: 14pt;
    font-weight: bold;
    color: #1565C0;
    margin: 10px 0 5px;
  }}
  .meta-table {{
    width: 100%;
    margin-bottom: 15px;
  }}
  .meta-table td {{
    padding: 3px 0;
  }}
  .meta-right {{
    text-align: right;
  }}
  .divider {{
    border: none;
    border-top: 1px solid #E2E8F0;
    margin: 12px 0;
  }}
  .paid-box {{
    text-align: center;
    padding: 15px 0;
  }}
  .paid-badge {{
    font-size: 16pt;
    font-weight: bold;
    color: #16A34A;
  }}
  .amount {{
    font-size: 32pt;
    font-weight: bold;
    color: #16A34A;
    margin: 5px 0;
  }}
  .method {{
    font-size: 10pt;
    color: #94A3B8;
  }}
  .details {{
    width: 100%;
    border-collapse: collapse;
    margin-top: 10px;
  }}
  .details .section-head {{
    background-color: #F8FAFC;
    font-size: 9pt;
    font-weight: bold;
    color: #1565C0;
    padding: 7px 10px;
    border-top: 1px solid #1565C0;
  }}
  .details .label {{
    width: 35%;
    padding: 7px 10px;
    font-size: 10pt;
    color: #64748B;
    border-bottom: 1px solid #E2E8F0;
  }}
  .details .value {{
    padding: 7px 10px;
    font-weight: bold;
    border-bottom: 1px solid #E2E8F0;
  }}
  .details .value.success {{
    color: #16A34A;
  }}
  .details .value.mono {{
    font-family: Courier;
    font-size: 9pt;
  }}
  .footer {{
    text-align: center;
    margin-top: 30px;
    padding-top: 10px;
    border-top: 1px solid #E2E8F0;
  }}
  .footer .thanks {{
    font-size: 11pt;
    font-weight: bold;
    color: #1565C0;
    margin-bottom: 4px;
  }}
  .footer .contact {{
    font-size: 9pt;
    color: #94A3B8;
  }}
  .footer .legal {{
    font-size: 8pt;
    color: #94A3B8;
    font-style: italic;
    margin-top: 10px;
  }}
</style>
</head>
<body>

<div class="header">
  <p class="brand">AQUATHLETIC</p>
  <p class="tagline">Swimming Academy</p>
  <p class="branch">{branch_name} Branch</p>
</div>

<p class="receipt-title">PAYMENT RECEIPT</p>

<table class="meta-table">
  <tr>
    <td><b>Receipt No.</b> {receipt_number}</td>
    <td class="meta-right"><b>Date:</b> {_format_date(issued_at)}</td>
  </tr>
</table>

<hr class="divider">

<div class="paid-box">
  <div class="paid-badge">&#10003; PAID</div>
  <div class="amount">{amount_paid} EGP</div>
  <div class="method">Payment Method: {channel}</div>
</div>

<hr class="divider">

<table class="details">
  <tr><td colspan="2" class="section-head">ATHLETE DETAILS</td></tr>
  <tr><td class="label">Name</td><td class="value">{athlete_name}</td></tr>
  <tr><td class="label">Athlete No.</td><td class="value">M{athlete_number}</td></tr>
  <tr><td class="label">Branch</td><td class="value">{branch_name}</td></tr>
  {"<tr><td class='label'>Level</td><td class='value'>" + level + "</td></tr>" if level else ""}
  {"<tr><td class='label'>Training Type</td><td class='value'>" + athlete_type + "</td></tr>" if athlete_type else ""}
  {"<tr><td class='label'>Phone</td><td class='value'>" + (phone or "") + "</td></tr>" if phone else ""}
  <tr><td colspan="2" class="section-head">PAYMENT DETAILS</td></tr>
  <tr><td class="label">Period</td><td class="value">{_format_period(period)}</td></tr>
  <tr><td class="label">Amount Paid</td><td class="value success">{amount_paid} EGP</td></tr>
  <tr><td class="label">Payment Method</td><td class="value">{channel}</td></tr>
  {txn_line}
</table>

<div class="footer">
  <p class="thanks">Thank you for choosing Aquathletic Swimming Academy!</p>
  <p class="contact">For inquiries, please contact your branch reception.</p>
  <p class="legal">This is an electronically generated receipt and does not require a signature.</p>
  <p class="legal">Receipt ID: {receipt_number} | Generated: {issued_at.strftime('%Y-%m-%d %H:%M UTC')}</p>
</div>

</body>
</html>"""

    buffer = io.BytesIO()
    pisa.CreatePDF(html, dest=buffer)
    return buffer.getvalue()
