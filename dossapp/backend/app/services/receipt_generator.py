"""Professional receipt PDF generation using ReportLab."""

import io
from datetime import datetime, timezone

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, HRFlowable
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT


# Brand colors
_BRAND_DARK = colors.HexColor("#0D1B2A")
_BRAND_PRIMARY = colors.HexColor("#1565C0")
_BRAND_ACCENT = colors.HexColor("#00897B")
_BRAND_GOLD = colors.HexColor("#F9A825")
_BRAND_LIGHT_BG = colors.HexColor("#F8FAFC")
_BRAND_BORDER = colors.HexColor("#E2E8F0")
_TEXT_PRIMARY = colors.HexColor("#1E293B")
_TEXT_SECONDARY = colors.HexColor("#64748B")
_TEXT_MUTED = colors.HexColor("#94A3B8")
_SUCCESS = colors.HexColor("#16A34A")
_SUCCESS_BG = colors.HexColor("#F0FDF4")


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
    """Generate a professional branded receipt PDF. Returns PDF bytes."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=25 * mm,
        leftMargin=25 * mm,
        topMargin=20 * mm,
        bottomMargin=20 * mm,
    )

    styles = getSampleStyleSheet()

    # ── Custom styles ──
    brand_name_style = ParagraphStyle(
        "BrandName", parent=styles["Heading1"],
        fontSize=28, fontName="Helvetica-Bold",
        alignment=TA_CENTER, spaceAfter=1 * mm,
        textColor=_BRAND_DARK,
    )
    tagline_style = ParagraphStyle(
        "Tagline", parent=styles["Normal"],
        fontSize=10, alignment=TA_CENTER,
        spaceAfter=1 * mm, textColor=_BRAND_PRIMARY,
        fontName="Helvetica-Oblique",
    )
    branch_style = ParagraphStyle(
        "Branch", parent=styles["Normal"],
        fontSize=12, alignment=TA_CENTER,
        spaceAfter=4 * mm, textColor=_TEXT_SECONDARY,
        fontName="Helvetica-Bold",
    )
    receipt_title_style = ParagraphStyle(
        "ReceiptTitle", parent=styles["Normal"],
        fontSize=14, alignment=TA_CENTER,
        spaceAfter=2 * mm, textColor=_BRAND_PRIMARY,
        fontName="Helvetica-Bold",
    )
    label_style = ParagraphStyle(
        "Label", parent=styles["Normal"],
        fontSize=10, textColor=_TEXT_SECONDARY,
        fontName="Helvetica",
    )
    value_style = ParagraphStyle(
        "Value", parent=styles["Normal"],
        fontSize=11, textColor=_TEXT_PRIMARY,
        fontName="Helvetica-Bold",
    )
    amount_style = ParagraphStyle(
        "Amount", parent=styles["Heading1"],
        fontSize=32, alignment=TA_CENTER,
        textColor=_SUCCESS, fontName="Helvetica-Bold",
        spaceAfter=2 * mm,
    )
    amount_label_style = ParagraphStyle(
        "AmountLabel", parent=styles["Normal"],
        fontSize=10, alignment=TA_CENTER,
        textColor=_TEXT_MUTED, fontName="Helvetica",
        spaceAfter=4 * mm,
    )
    paid_badge_style = ParagraphStyle(
        "PaidBadge", parent=styles["Heading1"],
        fontSize=16, alignment=TA_CENTER,
        textColor=_SUCCESS, fontName="Helvetica-Bold",
    )
    footer_style = ParagraphStyle(
        "Footer", parent=styles["Normal"],
        fontSize=9, alignment=TA_CENTER,
        textColor=_TEXT_MUTED,
    )
    legal_style = ParagraphStyle(
        "Legal", parent=styles["Normal"],
        fontSize=8, alignment=TA_CENTER,
        textColor=_TEXT_MUTED, fontName="Helvetica-Oblique",
    )

    if issued_at is None:
        issued_at = datetime.now(timezone.utc)

    elements = []

    # ══════════════════════════════════════════════════════════
    # HEADER — Brand identity
    # ══════════════════════════════════════════════════════════
    elements.append(Paragraph("AQUATHLETIC", brand_name_style))
    elements.append(Paragraph("Swimming Academy", tagline_style))
    elements.append(Paragraph(f"{branch_name} Branch", branch_style))

    # Gold accent line
    elements.append(HRFlowable(width="60%", thickness=2, color=_BRAND_GOLD, hAlign="CENTER"))
    elements.append(Spacer(1, 6 * mm))

    # ══════════════════════════════════════════════════════════
    # RECEIPT HEADER
    # ══════════════════════════════════════════════════════════
    elements.append(Paragraph("PAYMENT RECEIPT", receipt_title_style))
    elements.append(Spacer(1, 3 * mm))

    # Receipt number + date row
    meta_data = [
        [
            Paragraph(f"<b>Receipt No.</b>", label_style),
            Paragraph(f"<b>Date</b>", ParagraphStyle("RightLabel", parent=label_style, alignment=TA_RIGHT)),
        ],
        [
            Paragraph(f"{receipt_number}", value_style),
            Paragraph(
                f"{issued_at.strftime('%d %b %Y, %I:%M %p')}",
                ParagraphStyle("RightValue", parent=value_style, alignment=TA_RIGHT),
            ),
        ],
    ]
    meta_table = Table(meta_data, colWidths=["50%", "50%"])
    meta_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 2),
        ("TOPPADDING", (0, 1), (-1, 1), 0),
    ]))
    elements.append(meta_table)
    elements.append(Spacer(1, 5 * mm))

    # ══════════════════════════════════════════════════════════
    # AMOUNT — Big and prominent
    # ══════════════════════════════════════════════════════════
    # Paid badge + amount in a styled box
    elements.append(HRFlowable(width="100%", thickness=0.5, color=_BRAND_BORDER))
    elements.append(Spacer(1, 5 * mm))

    elements.append(Paragraph("✓ PAID", paid_badge_style))
    elements.append(Spacer(1, 2 * mm))
    elements.append(Paragraph(f"{amount_paid} EGP", amount_style))
    elements.append(Paragraph(f"Payment Method: {payment_channel}", amount_label_style))

    elements.append(HRFlowable(width="100%", thickness=0.5, color=_BRAND_BORDER))
    elements.append(Spacer(1, 5 * mm))

    # ══════════════════════════════════════════════════════════
    # DETAILS TABLE
    # ══════════════════════════════════════════════════════════
    detail_rows = [
        [Paragraph("ATHLETE DETAILS", ParagraphStyle(
            "SectionHead", parent=label_style,
            fontName="Helvetica-Bold", fontSize=9, textColor=_BRAND_PRIMARY,
        )), ""],
    ]
    detail_rows.append([
        Paragraph("Name", label_style),
        Paragraph(athlete_name, value_style),
    ])
    detail_rows.append([
        Paragraph("Athlete No.", label_style),
        Paragraph(f"M{athlete_number}", value_style),
    ])
    detail_rows.append([
        Paragraph("Branch", label_style),
        Paragraph(branch_name, value_style),
    ])
    if level:
        detail_rows.append([
            Paragraph("Level", label_style),
            Paragraph(level, value_style),
        ])
    if athlete_type:
        detail_rows.append([
            Paragraph("Training Type", label_style),
            Paragraph(athlete_type, value_style),
        ])
    if phone:
        detail_rows.append([
            Paragraph("Phone", label_style),
            Paragraph(phone, value_style),
        ])

    # Separator row
    detail_rows.append(["", ""])

    detail_rows.append([
        Paragraph("PAYMENT DETAILS", ParagraphStyle(
            "SectionHead2", parent=label_style,
            fontName="Helvetica-Bold", fontSize=9, textColor=_BRAND_PRIMARY,
        )), "",
    ])
    detail_rows.append([
        Paragraph("Period", label_style),
        Paragraph(period, value_style),
    ])
    detail_rows.append([
        Paragraph("Amount Paid", label_style),
        Paragraph(f"{amount_paid} EGP", ParagraphStyle(
            "AmountValue", parent=value_style, textColor=_SUCCESS,
        )),
    ])
    detail_rows.append([
        Paragraph("Payment Method", label_style),
        Paragraph(payment_channel, value_style),
    ])
    if paymob_transaction_id:
        detail_rows.append([
            Paragraph("Transaction ID", label_style),
            Paragraph(paymob_transaction_id, ParagraphStyle(
                "TxnId", parent=value_style, fontSize=9, fontName="Courier",
            )),
        ])

    detail_table = Table(detail_rows, colWidths=[45 * mm, 115 * mm])
    detail_table.setStyle(TableStyle([
        # Section headers
        ("SPAN", (0, 0), (1, 0)),
        ("BACKGROUND", (0, 0), (1, 0), _BRAND_LIGHT_BG),
        # Data rows
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        # Borders
        ("LINEBELOW", (0, 0), (-1, -2), 0.5, _BRAND_BORDER),
        ("LINEABOVE", (0, 0), (-1, 0), 1, _BRAND_PRIMARY),
        ("LINEBELOW", (0, -1), (-1, -1), 1, _BRAND_PRIMARY),
        # Alternating rows
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, _BRAND_LIGHT_BG]),
    ]))

    # Find and style separator + payment section header rows
    sep_idx = len(detail_rows) - 5  # approximate separator row
    for i, row in enumerate(detail_rows):
        if row == ["", ""]:
            detail_table.setStyle(TableStyle([
                ("SPAN", (0, i), (1, i)),
                ("TOPPADDING", (0, i), (-1, i), 2),
                ("BOTTOMPADDING", (0, i), (-1, i), 2),
                ("LINEBELOW", (0, i), (-1, i), 0, colors.white),
            ]))
        if isinstance(row[0], Paragraph) and "PAYMENT DETAILS" in str(row[0]):
            detail_table.setStyle(TableStyle([
                ("SPAN", (0, i), (1, i)),
                ("BACKGROUND", (0, i), (1, i), _BRAND_LIGHT_BG),
            ]))

    elements.append(detail_table)

    # ══════════════════════════════════════════════════════════
    # FOOTER
    # ══════════════════════════════════════════════════════════
    elements.append(Spacer(1, 15 * mm))
    elements.append(HRFlowable(width="100%", thickness=0.5, color=_BRAND_BORDER))
    elements.append(Spacer(1, 4 * mm))

    elements.append(Paragraph(
        "Thank you for choosing Aquathletic Swimming Academy!",
        ParagraphStyle("ThankYou", parent=footer_style, fontSize=11,
                       textColor=_BRAND_PRIMARY, fontName="Helvetica-Bold"),
    ))
    elements.append(Spacer(1, 2 * mm))
    elements.append(Paragraph(
        "For inquiries, please contact your branch reception.",
        footer_style,
    ))
    elements.append(Spacer(1, 6 * mm))
    elements.append(Paragraph(
        "This is an electronically generated receipt and does not require a signature.",
        legal_style,
    ))
    elements.append(Paragraph(
        f"Receipt ID: {receipt_number} | Generated: {issued_at.strftime('%Y-%m-%d %H:%M UTC')}",
        legal_style,
    ))

    doc.build(elements)
    return buffer.getvalue()
