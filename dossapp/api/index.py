"""Vercel serverless entry point — thin wrapper around the FastAPI app."""

import os
import sys

# Ensure backend package is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

# Convert Neon's postgresql:// URL to asyncpg driver format
db_url = os.environ.get("DATABASE_URL", "")
if db_url.startswith("postgresql://"):
    db_url = db_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    # Remove params not supported by asyncpg (channel_binding, sslmode)
    # asyncpg handles SSL via the 'ssl' connect arg, not URL params
    from urllib.parse import urlparse, parse_qs, urlencode, urlunparse
    parsed = urlparse(db_url)
    params = {k: v[0] for k, v in parse_qs(parsed.query).items()
              if k not in ("channel_binding", "sslmode")}
    db_url = urlunparse(parsed._replace(query=urlencode(params)))
    os.environ["DATABASE_URL"] = db_url
elif not db_url:
    os.environ["DATABASE_URL"] = "sqlite+aiosqlite:////tmp/aqua_athletic.db"

# Set root_path so FastAPI matches routes under /api
os.environ.setdefault("VERCEL", "1")

from app.main import app  # noqa: E402

# Override root_path so routes like /auth/customer/login
# match when Vercel sends /api/auth/customer/login
app.root_path = "/api"

# Vercel looks for `app` or `handler` at module level
