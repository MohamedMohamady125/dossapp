from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase

from app.config import settings

# Auto-fix DATABASE_URL: ensure async driver prefix no matter what the user pastes
_db_url = settings.database_url
if _db_url.startswith("postgres://"):
    _db_url = _db_url.replace("postgres://", "postgresql+asyncpg://", 1)
elif _db_url.startswith("postgresql://"):
    _db_url = _db_url.replace("postgresql://", "postgresql+asyncpg://", 1)

_is_sqlite = _db_url.startswith("sqlite")
_is_neon = "neon" in _db_url

engine_kwargs: dict = {"echo": False}
if _is_sqlite:
    engine_kwargs["connect_args"] = {"check_same_thread": False}
else:
    engine_kwargs["pool_size"] = 5
    engine_kwargs["max_overflow"] = 5
    # Only Neon/cloud PostgreSQL needs ssl=True; Railway internal Postgres does not
    if _is_neon:
        engine_kwargs["connect_args"] = {"ssl": True}

engine = create_async_engine(_db_url, **engine_kwargs)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def _add_missing_columns(sync_conn):
    """Additive micro-migrations for existing databases (create_all won't alter tables)."""
    from sqlalchemy import inspect, text

    insp = inspect(sync_conn)
    if "admin_users" in insp.get_table_names():
        cols = {c["name"] for c in insp.get_columns("admin_users")}
        if "coach_name" not in cols:
            sync_conn.execute(text("ALTER TABLE admin_users ADD COLUMN coach_name VARCHAR(255)"))
        if "must_change_password" not in cols:
            sync_conn.execute(text(
                "ALTER TABLE admin_users ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE"
            ))


async def init_db():
    """Create all tables if they don't exist."""
    import app.models  # noqa: F401 — ensure all models are registered with Base
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(_add_missing_columns)


async def get_db() -> AsyncSession:  # type: ignore[misc]
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
