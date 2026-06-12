"""Professional receipt PDF generation using ReportLab."""

import io
from datetime import datetime, timezone

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, HRFlowable
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT


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
    """Generate a professional receipt PDF. Returns PDF bytes."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=20 * mm,
        leftMargin=20 * mm,
        topMargin=15 * mm,
        bottomMargin=15 * mm,
    )

    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        "ReceiptTitle",
        parent=styles["Heading1"],
        fontSize=22,
        alignment=TA_CENTER,
        spaceAfter=2 * mm,
        textColor=colors.HexColor("#1a237e"),
    )
    subtitle_style = ParagraphStyle(
        "ReceiptSubtitle",
        parent=styles["Normal"],
        fontSize=11,
        alignment=TA_CENTER,
        spaceAfter=5 * mm,
        textColor=colors.HexColor("#424242"),
    )
    label_style = ParagraphStyle(
        "Label",
        parent=styles["Normal"],
        fontSize=10,
        textColor=colors.HexColor("#757575"),
    )
    value_style = ParagraphStyle(
        "Value",
        parent=styles["Normal"],
        fontSize=11,
        textColor=colors.HexColor("#212121"),
        fontName="Helvetica-Bold",
    )
    paid_style = ParagraphStyle(
        "Paid",
        parent=styles["Heading1"],
        fontSize=28,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#2e7d32"),
        spaceAfter=5 * mm,
    )
    footer_style = ParagraphStyle(
        "Footer",
        parent=styles["Normal"],
        fontSize=9,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#9e9e9e"),
    )

    if issued_at is None:
        issued_at = datetime.now(timezone.utc)

    elements = []

    # Header
    elements.append(Paragraph("Aqua Athletic Academy", title_style))
    elements.append(Paragraph(f"{branch_name} Branch", subtitle_style))
    elements.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#1a237e")))
    elements.append(Spacer(1, 5 * mm))

    # Receipt number and date row
    header_data = [
        [
            Paragraph(f"Receipt No: <b>{receipt_number}</b>", styles["Normal"]),
            Paragraph(f"Date: <b>{issued_at.strftime('%d %b %Y, %I:%M %p')}</b>",
                      ParagraphStyle("Right", parent=styles["Normal"], alignment=TA_RIGHT)),
        ]
    ]
    header_table = Table(header_data, colWidths=["50%", "50%"])
    header_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    elements.append(header_table)
    elements.append(Spacer(1, 5 * mm))

    # PAID stamp
    elements.append(Paragraph("PAID", paid_style))
    elements.append(Spacer(1, 3 * mm))

    # Details table
    detail_rows = [
        ["Athlete Name", athlete_name],
        ["Athlete Number", str(athlete_number)],
        ["Branch", branch_name],
    ]
    if level:
        detail_rows.append(["Level", level])
    if athlete_type:
        detail_rows.append(["Type", athlete_type])
    if phone:
        detail_rows.append(["Phone", phone])
    detail_rows.append(["Period", period])
    detail_rows.append(["Amount Paid", f"{amount_paid} EGP"])
    detail_rows.append(["Payment Method", payment_channel])
    if paymob_transaction_id:
        detail_rows.append(["Transaction ID", paymob_transaction_id])

    detail_table = Table(detail_rows, colWidths=[45 * mm, 120 * mm])
    detail_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f5f5f5")),
        ("TEXTCOLOR", (0, 0), (0, -1), colors.HexColor("#616161")),
        ("FONTNAME", (1, 0), (1, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e0e0e0")),
        ("ROWBACKGROUNDS", (0, 0), (-1, -1), [colors.white, colors.HexColor("#fafafa")]),
    ]))
    elements.append(detail_table)

    elements.append(Spacer(1, 15 * mm))
    elements.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#e0e0e0")))
    elements.append(Spacer(1, 3 * mm))

    # Footer
    elements.append(Paragraph("Thank you for choosing Aqua Athletic Academy!", footer_style))
    elements.append(Paragraph("For inquiries, please contact your branch reception.", footer_style))

    doc.build(elements)
    return buffer.getvalue()
