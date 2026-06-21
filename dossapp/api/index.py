"""Vercel serverless entry point — thin wrapper around the FastAPI app."""

import os
import sys

# Ensure backend package is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

# Force SQLite to use /tmp on Vercel (only writable dir)
if not os.environ.get("DATABASE_URL"):
    os.environ["DATABASE_URL"] = "sqlite+aiosqlite:////tmp/aqua_athletic.db"

# Set root_path so FastAPI matches routes under /api
os.environ.setdefault("VERCEL", "1")

from app.main import app  # noqa: E402

# Override root_path so routes like /auth/customer/login
# match when Vercel sends /api/auth/customer/login
app.root_path = "/api"

# Vercel looks for `app` or `handler` at module level
