from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase

from app.config import settings

_is_sqlite = settings.database_url.startswith("sqlite")

engine_kwargs: dict = {"echo": False}
if _is_sqlite:
    engine_kwargs["connect_args"] = {"check_same_thread": False}
else:
    engine_kwargs["pool_size"] = 5
    engine_kwargs["max_overflow"] = 5
    # asyncpg requires ssl=True for Neon/cloud PostgreSQL
    engine_kwargs["connect_args"] = {"ssl": True}

engine = create_async_engine(settings.database_url, **engine_kwargs)
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
