"""Easykash Direct Pay integration — hosted checkout creation + callback signature verification.

No public docs exist; endpoint shape and callback signature come from the merchant
dashboard. Payment option codes and signature field order are configurable via env
(EASYKASH_PAYMENT_OPTIONS, EASYKASH_SIGNATURE_FIELDS) so corrections from Easykash
support are a config change, not a code change.
"""

import hashlib
import hmac
import logging
from decimal import Decimal
from typing import Optional

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

EASYKASH_PAY_URL = "https://back.easykash.net/api/directpayv1/pay"


def _payment_options() -> list[int]:
    raw = settings.easykash_payment_options.strip()
    if not raw:
        return []
    options = []
    for part in raw.split(","):
        part = part.strip()
        if part.isdigit():
            options.append(int(part))
    return options


async def create_checkout(
    amount_egp: Decimal,
    athlete_name: str,
    athlete_number: int,
    branch_id: int,
    period: str,
    phone: Optional[str] = None,
    email: Optional[str] = None,
) -> Optional[dict]:
    """Create an Easykash hosted-checkout session.

    Returns {"url": <checkout url>} or None on error.
    Amount is in EGP units (not cents).
    """
    if not settings.easykash_api_key:
        logger.warning("Easykash API key not configured")
        return None

    payload = {
        "amount": str(amount_egp),
        "currency": "EGP",
        "paymentOptions": _payment_options(),
        "cashExpiry": 48,
        "name": athlete_name or "Athlete",
        "email": email or "customer@aquaathletic.com",
        "mobile": phone or "+201000000000",
        "redirectUrl": f"{settings.public_base_url}/pay/success",
        "customerReference": f"AQUA-{branch_id}-{athlete_number}-{period}",
    }

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                EASYKASH_PAY_URL,
                json=payload,
                headers={"Authorization": settings.easykash_api_key},
            )
    except httpx.HTTPError as e:
        logger.error(f"Easykash checkout request failed: {e}")
        return None

    if resp.status_code >= 300:
        logger.error(f"Easykash checkout failed ({resp.status_code}): {resp.text[:500]}")
        return None

    try:
        data = resp.json()
    except ValueError:
        logger.error(f"Easykash checkout returned non-JSON: {resp.text[:500]}")
        return None

    url = data.get("redirectUrl") or data.get("url") or data.get("paymentUrl")
    if not url:
        logger.error(f"Easykash checkout response missing redirect url: {data}")
        return None

    return {"url": url}


def verify_signature(payload: dict, received: str) -> bool:
    """Verify the Easykash callback signatureHash (HMAC-SHA256, hex).

    Field order comes from EASYKASH_SIGNATURE_FIELDS. On mismatch, logs the
    concatenated string and computed hash (never the secret) so the correct
    field order can be determined from a single real callback.
    """
    if not settings.easykash_hmac_secret or not received:
        return False

    fields = [f.strip() for f in settings.easykash_signature_fields.split(",") if f.strip()]
    concatenated = "".join(str(payload.get(f, "")) for f in fields)

    computed = hmac.new(
        settings.easykash_hmac_secret.encode("utf-8"),
        concatenated.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if hmac.compare_digest(computed.lower(), received.lower()):
        return True

    logger.warning(
        "Easykash signature mismatch: fields=%s concatenated=%r computed=%s received=%s",
        fields, concatenated, computed, received,
    )
    return False
