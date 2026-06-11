"""Phone number normalization — dirty Excel values → E.164 (Egypt +20)."""

import re
import phonenumbers


def normalize_phone(raw: str | None) -> str | None:
    """Best-effort normalize a dirty phone string to E.164 (+20...).

    Returns None if the value cannot be parsed into a valid number.
    """
    if not raw:
        return None

    cleaned = str(raw).strip()
    if not cleaned:
        return None

    # Remove common noise: backslashes, quotes, spaces, dashes, parens
    cleaned = re.sub(r"[\\\"'\s\-\(\)]+", "", cleaned)

    # Handle scientific notation floats (e.g. 1.01E+12)
    if "E+" in cleaned.upper() or "e+" in cleaned:
        try:
            cleaned = str(int(float(cleaned)))
        except (ValueError, OverflowError):
            return None

    # Remove trailing .0 from float-like strings
    if cleaned.endswith(".0"):
        cleaned = cleaned[:-2]

    # Strip any remaining non-digit characters except leading +
    if cleaned.startswith("+"):
        cleaned = "+" + re.sub(r"[^\d]", "", cleaned[1:])
    else:
        cleaned = re.sub(r"[^\d]", "", cleaned)

    if not cleaned or len(cleaned) < 7:
        return None

    try:
        # Try parsing as Egyptian number first
        parsed = phonenumbers.parse(cleaned, "EG")
        if phonenumbers.is_valid_number(parsed):
            return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
    except phonenumbers.NumberParseException:
        pass

    # Try with explicit + prefix
    if not cleaned.startswith("+"):
        try:
            parsed = phonenumbers.parse("+" + cleaned, None)
            if phonenumbers.is_valid_number(parsed):
                return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
        except phonenumbers.NumberParseException:
            pass

    return None
