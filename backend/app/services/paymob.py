"""Paymob payment integration — intent creation + webhook verification."""

import hashlib
import hmac
import logging
from decimal import Decimal
from typing import Optional

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

PAYMOB_BASE_URL = "https://accept.paymob.com/api"


async def create_payment_intent(
    amount_egp: Decimal,
    athlete_name: str,
    athlete_number: int,
    branch_id: int,
    period: str,
    phone: Optional[str] = None,
    email: Optional[str] = None,
) -> Optional[dict]:
    """Create a Paymob payment intent. Returns {token, order_id} or None on error.

    Amount is in EGP — Paymob expects amount in cents (piastres).
    """
    amount_cents = int(amount_egp * 100)

    async with httpx.AsyncClient() as client:
        # Step 1: Auth
        auth_resp = await client.post(
            f"{PAYMOB_BASE_URL}/auth/tokens",
            json={"api_key": settings.paymob_api_key},
        )
        auth_resp.raise_for_status()
        auth_token = auth_resp.json()["token"]

        # Step 2: Create order
        order_resp = await client.post(
            f"{PAYMOB_BASE_URL}/ecommerce/orders",
            json={
                "auth_token": auth_token,
                "delivery_needed": False,
                "amount_cents": amount_cents,
                "currency": "EGP",
                "items": [{
                    "name": f"Swimming lessons - {period}",
                    "amount_cents": amount_cents,
                    "description": f"Athlete #{athlete_number}, Branch {branch_id}",
                    "quantity": 1,
                }],
                "merchant_order_id": f"AQUA-{branch_id}-{athlete_number}-{period}",
            },
        )
        order_resp.raise_for_status()
        order_id = order_resp.json()["id"]

        # Step 3: Payment key
        billing = {
            "first_name": athlete_name.split()[0] if athlete_name else "Athlete",
            "last_name": " ".join(athlete_name.split()[1:]) if athlete_name and len(athlete_name.split()) > 1 else ".",
            "email": email or "customer@aquaathletic.com",
            "phone_number": phone or "+201000000000",
            "apartment": "NA", "floor": "NA", "street": "NA",
            "building": "NA", "shipping_method": "NA",
            "postal_code": "NA", "city": "Cairo",
            "country": "EG", "state": "Cairo",
        }

        key_resp = await client.post(
            f"{PAYMOB_BASE_URL}/acceptance/payment_keys",
            json={
                "auth_token": auth_token,
                "amount_cents": amount_cents,
                "expiration": 3600,
                "order_id": order_id,
                "billing_data": billing,
                "currency": "EGP",
                "integration_id": int(settings.paymob_integration_id) if settings.paymob_integration_id else 0,
            },
        )
        key_resp.raise_for_status()
        payment_token = key_resp.json()["token"]

        return {"token": payment_token, "order_id": order_id}


def verify_hmac(request_data: dict, received_hmac: str) -> bool:
    """Verify Paymob webhook HMAC signature."""
    # Paymob HMAC is computed over specific concatenated fields
    hmac_fields = [
        "amount_cents", "created_at", "currency", "error_occured",
        "has_parent_transaction", "id", "integration_id", "is_3d_secure",
        "is_auth", "is_capture", "is_refunded", "is_standalone_payment",
        "is_voided", "order.id", "owner", "pending",
        "source_data.pan", "source_data.sub_type", "source_data.type", "success",
    ]

    def _get_nested(data: dict, key: str):
        parts = key.split(".")
        val = data
        for p in parts:
            if isinstance(val, dict):
                val = val.get(p, "")
            else:
                return ""
        return str(val).lower() if isinstance(val, bool) else str(val)

    concatenated = "".join(_get_nested(request_data, f) for f in hmac_fields)

    computed = hmac.new(
        settings.paymob_hmac_secret.encode("utf-8"),
        concatenated.encode("utf-8"),
        hashlib.sha512,
    ).hexdigest()

    return hmac.compare_digest(computed, received_hmac)
