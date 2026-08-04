"""Billing period utilities."""

from datetime import datetime


def current_billing_period() -> str:
    """Return the current billing period as YYYY-MM.

    On the 25th or later, the billing period rolls to next month
    (that's when the admin swaps the Excel sheet to the new month).
    """
    now = datetime.now()
    if now.day >= 25:
        # Roll to next month
        if now.month == 12:
            return f"{now.year + 1}-01"
        return f"{now.year}-{now.month + 1:02d}"
    return now.strftime("%Y-%m")
