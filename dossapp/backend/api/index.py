"""Vercel serverless entry point — thin wrapper around the FastAPI app."""

import os
import sys

# Ensure backend package is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# Force SQLite to use /tmp on Vercel (only writable dir)
if not os.environ.get("DATABASE_URL"):
    os.environ["DATABASE_URL"] = "sqlite+aiosqlite:////tmp/aqua_athletic.db"

from app.main import app  # noqa: E402 — the ASGI app Vercel will serve

# Vercel looks for `app` or `handler` at module level
