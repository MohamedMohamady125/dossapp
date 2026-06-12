"""Initial schema

Revision ID: 001
Revises:
Create Date: 2026-06-01
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "branches",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("name", sa.String(100), nullable=False, unique=True),
        sa.Column("display_name", sa.String(200), nullable=False),
        sa.Column("drive_file_id", sa.String(200), nullable=True),
    )

    op.create_table(
        "admin_users",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("username", sa.String(100), nullable=False, unique=True),
        sa.Column("email", sa.String(255), nullable=True, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("role", sa.String(20), nullable=False),
        sa.Column("assigned_branch_id", sa.Integer(), sa.ForeignKey("branches.id"), nullable=True),
        sa.Column("is_active", sa.Boolean(), default=True, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "accounts",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("branch_id", sa.Integer(), sa.ForeignKey("branches.id"), nullable=False),
        sa.Column("athlete_number", sa.Integer(), nullable=False),
        sa.Column("login_code", sa.String(50), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("must_change_password", sa.Boolean(), default=True, nullable=False),
        sa.Column("name_at_creation", sa.String(300), nullable=False),
        sa.Column("dob_at_creation", sa.String(50), nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("phone_at_creation", sa.String(50), nullable=True),
        sa.Column("status", sa.String(30), default="active", nullable=False),
        sa.Column("created_by_admin_id", sa.Integer(), sa.ForeignKey("admin_users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_unique_constraint("uq_account_branch_athlete", "accounts", ["branch_id", "athlete_number"])
    op.create_index("ix_account_branch_athlete", "accounts", ["branch_id", "athlete_number"])
    op.create_index("ix_account_login_code", "accounts", ["login_code"])

    op.create_table(
        "payments",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("branch_id", sa.Integer(), sa.ForeignKey("branches.id"), nullable=False),
        sa.Column("athlete_number", sa.Integer(), nullable=False),
        sa.Column("period", sa.String(10), nullable=False),
        sa.Column("source", sa.String(20), nullable=False),
        sa.Column("amount_owed_snapshot", sa.Numeric(12, 2), nullable=True),
        sa.Column("amount_paid", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(5), default="EGP", nullable=False),
        sa.Column("paymob_transaction_id", sa.String(100), nullable=True),
        sa.Column("excel_receipt_no", sa.String(100), nullable=True),
        sa.Column("status", sa.String(20), default="pending", nullable=False),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_unique_constraint("uq_payment_idempotent", "payments", ["branch_id", "athlete_number", "period", "source"])
    op.create_index("ix_payment_branch_athlete", "payments", ["branch_id", "athlete_number"])
    op.create_index("ix_payment_period", "payments", ["period"])
    op.create_index("ix_payment_status", "payments", ["status"])

    op.create_table(
        "receipts",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("payment_id", sa.Integer(), sa.ForeignKey("payments.id"), nullable=False, unique=True),
        sa.Column("receipt_number", sa.String(50), nullable=False, unique=True),
        sa.Column("pdf_data", sa.LargeBinary(), nullable=True),
        sa.Column("issued_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("athlete_name", sa.String(300), nullable=False),
        sa.Column("athlete_number", sa.Integer(), nullable=False),
        sa.Column("branch_name", sa.String(200), nullable=False),
        sa.Column("level", sa.String(100), nullable=True),
        sa.Column("athlete_type", sa.String(100), nullable=True),
        sa.Column("phone", sa.String(50), nullable=True),
        sa.Column("period", sa.String(10), nullable=False),
        sa.Column("amount_paid", sa.String(20), nullable=False),
        sa.Column("payment_channel", sa.String(20), nullable=False),
        sa.Column("paymob_transaction_id", sa.String(100), nullable=True),
        sa.Column("send_status", sa.JSON(), default=dict, nullable=False),
    )

    op.create_table(
        "notification_log",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("receipt_id", sa.Integer(), sa.ForeignKey("receipts.id"), nullable=True),
        sa.Column("account_id", sa.Integer(), sa.ForeignKey("accounts.id"), nullable=True),
        sa.Column("channel", sa.String(20), nullable=False),
        sa.Column("to", sa.String(255), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("error", sa.String(500), nullable=True),
        sa.Column("attempts", sa.Integer(), default=0, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("notification_log")
    op.drop_table("receipts")
    op.drop_table("payments")
    op.drop_table("accounts")
    op.drop_table("admin_users")
    op.drop_table("branches")
