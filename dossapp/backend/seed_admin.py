"""Seed the first admin user and branches.

Usage:
    python seed_admin.py

Creates the initial admin account and 7 branch records.
"""

import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from app.database import async_session, engine
from app.database import Base
from app.models import *  # noqa
from app.models.admin_user import AdminUser
from app.models.branch import Branch
from app.utils.auth import hash_password


BRANCHES = [
    {"name": "branch_1", "display_name": "Branch 1"},
    {"name": "branch_2", "display_name": "Branch 2"},
    {"name": "branch_3", "display_name": "Branch 3"},
    {"name": "branch_4", "display_name": "Branch 4"},
    {"name": "branch_5", "display_name": "Branch 5"},
    {"name": "branch_6", "display_name": "Branch 6"},
    {"name": "branch_7", "display_name": "Branch 7"},
]


async def seed():
    # Create tables if they don't exist
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as db:
        # Seed branches
        from sqlalchemy import select
        existing = await db.execute(select(Branch))
        if not existing.scalars().first():
            for i, b in enumerate(BRANCHES, 1):
                from app.config import settings
                drive_id = getattr(settings, f"drive_file_id_branch_{i}", "")
                branch = Branch(
                    name=b["name"],
                    display_name=b["display_name"],
                    drive_file_id=drive_id or None,
                )
                db.add(branch)
            await db.flush()
            print(f"Created {len(BRANCHES)} branches")
        else:
            print("Branches already exist, skipping")

        # Seed admin user
        existing_admin = await db.execute(
            select(AdminUser).where(AdminUser.username == "admin")
        )
        if not existing_admin.scalars().first():
            admin = AdminUser(
                username="admin",
                email="admin@aquaathletic.com",
                password_hash=hash_password("admin123"),  # Change in production!
                role="admin",
                is_active=True,
            )
            db.add(admin)
            print("Created admin user: username='admin', password='admin123'")
            print("  >>> CHANGE THIS PASSWORD IN PRODUCTION! <<<")
        else:
            print("Admin user already exists, skipping")

        await db.commit()

    print("\nSeed complete.")


if __name__ == "__main__":
    asyncio.run(seed())
