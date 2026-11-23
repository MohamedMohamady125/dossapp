from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # Database (SQLite for local dev, PostgreSQL for production)
    database_url: str = "sqlite+aiosqlite:///./aqua_athletic.db"

    # JWT
    jwt_secret_key: str = "change-me"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    # Parents open the app about once a month, to pay. A short refresh
    # window signs them out between visits.
    jwt_refresh_token_expire_days: int = 90

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

    # Easykash payment gateway
    easykash_api_key: str = ""  # private API key from seller dashboard (Authorization header)
    easykash_hmac_secret: str = ""  # HMAC secretKey from seller dashboard
    easykash_payment_options: str = ""  # comma-separated method codes, e.g. "2,4,6"
    easykash_signature_fields: str = "ProductCode,Amount,ProductType,PaymentMethod,status,easykashRef,customerReference"
    easykash_allow_unverified: bool = False  # dev only: accept callbacks without HMAC secret
    public_base_url: str = "https://dossapp-tau.vercel.app/api"  # for post-payment redirect

    # Notifications
    sms_provider: str = "stub"
    sms_api_key: str = ""
    sms_sender_id: str = "AQUA"

    email_provider: str = "stub"  # "stub" | "smtp" | "resend"
    email_smtp_host: str = ""
    email_smtp_port: int = 587
    email_smtp_user: str = ""
    email_smtp_password: str = ""
    email_from_address: str = "noreply@aquaathletic.com"
    resend_api_key: str = ""

    whatsapp_provider: str = "stub"
    # The message staff send to a parent with the login details. Change it with
    # the CREDENTIALS_MESSAGE_TEMPLATE variable; write \n for a new line.
    # Placeholders: {name} {code} {password} {branch}
    credentials_message_template: str = (
        "Aquathletic Academy\n"
        "App login details for {name}\n\n"
        "Login code: {code}\n"
        "Password: {password}\n\n"
        "You will be asked to choose your own password the first time you sign in."
    )
    whatsapp_api_key: str = ""
    whatsapp_phone_number_id: str = ""

    # Push notifications (Firebase Cloud Messaging)
    firebase_credentials_json: str = ""  # file path or inline JSON
    firebase_project_id: str = ""  # optional; falls back to project_id in credentials

    # Cron endpoint auth (Vercel sends Authorization: Bearer $CRON_SECRET)
    cron_secret: str = ""

    # Day of month for unpaid reminder
    payment_reminder_day: int = 25

    # Built-in daily scheduler (payment reminders, spot-lost). Hour is Egypt time.
    daily_jobs_enabled: bool = True
    daily_jobs_hour: int = 10

    # Excel refresh
    excel_refresh_interval_seconds: int = 60

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
