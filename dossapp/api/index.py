"""Vercel serverless entry point — thin wrapper around the FastAPI app."""

import os
import sys

# Ensure backend package is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

# Force SQLite to use /tmp on Vercel (only writable dir)
if not os.environ.get("DATABASE_URL"):
    os.environ["DATABASE_URL"] = "sqlite+aiosqlite:////tmp/aqua_athletic.db"

from fastapi import FastAPI  # noqa: E402
from app.main import app as backend_app  # noqa: E402

# Mount the backend app under /api so Vercel routes work correctly
app = FastAPI()
app.mount("/api", backend_app)

# Vercel looks for `app` or `handler` at module level
