"""JWT + password hashing utilities."""

import secrets
import string
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
from passlib.hash import argon2

from app.config import settings


def hash_password(password: str) -> str:
    return argon2.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return argon2.verify(password, password_hash)
    except Exception:
        return False


def generate_temp_password(length: int = 8) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def generate_login_code(branch_name: str, athlete_number: int) -> str:
    """Generate a deterministic, human-friendly login code."""
    prefix = branch_name[:3].upper().replace(" ", "")
    return f"{prefix}-{athlete_number:04d}"


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.jwt_access_token_expire_minutes)
    )
    to_encode["exp"] = expire
    to_encode["type"] = "access"
    return jwt.encode(to_encode, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def create_refresh_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.jwt_refresh_token_expire_days)
    to_encode["exp"] = expire
    to_encode["type"] = "refresh"
    return jwt.encode(to_encode, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> Optional[dict]:
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        return payload
    except JWTError:
        return None
