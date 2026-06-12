from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # Database (SQLite for local dev, PostgreSQL for production)
    database_url: str = "sqlite+aiosqlite:///./aqua_athletic.db"

    # JWT
    jwt_secret_key: str = "change-me"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 7

    # Google Drive
    google_drive_credentials_json: str = ""

    # Drive file IDs per branch
    drive_file_id_branch_1: str = ""
    drive_file_id_branch_2: str = ""
    drive_file_id_branch_3: str = ""
    drive_file_id_branch_4: str = ""
    drive_file_id_branch_5: str = ""
    drive_file_id_branch_6: str = ""
    drive_file_id_branch_7: str = ""

    # Paymob
    paymob_api_key: str = ""
    paymob_secret_key: str = ""
    paymob_hmac_secret: str = ""
    paymob_integration_id: str = ""

    # Notifications
    sms_provider: str = "stub"
    sms_api_key: str = ""
    sms_sender_id: str = "AQUA"

    email_provider: str = "stub"
    email_smtp_host: str = ""
    email_smtp_port: int = 587
    email_smtp_user: str = ""
    email_smtp_password: str = ""
    email_from_address: str = "noreply@aquaathletic.com"

    whatsapp_provider: str = "stub"
    whatsapp_api_key: str = ""
    whatsapp_phone_number_id: str = ""

    # Excel refresh
    excel_refresh_interval_seconds: int = 60

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
