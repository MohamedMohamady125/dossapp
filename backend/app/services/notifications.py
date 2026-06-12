"""Notification provider abstraction — SMS, Email, WhatsApp.

Concrete providers are swappable via config. Stub providers for development.
All sends are logged and retried on failure.
"""

import asyncio
import logging
from abc import ABC, abstractmethod
from typing import Optional

from app.config import settings

logger = logging.getLogger(__name__)


class NotificationProvider(ABC):
    @abstractmethod
    async def send_sms(self, to: str, body: str) -> bool:
        ...

    @abstractmethod
    async def send_email(self, to: str, subject: str, body: str, attachment: Optional[bytes] = None) -> bool:
        ...

    @abstractmethod
    async def send_whatsapp(self, to: str, body: str, attachment: Optional[bytes] = None) -> bool:
        ...


class StubProvider(NotificationProvider):
    """Development stub — logs but doesn't send."""

    async def send_sms(self, to: str, body: str) -> bool:
        logger.info(f"[STUB SMS] to={to} body={body[:80]}...")
        return True

    async def send_email(self, to: str, subject: str, body: str, attachment: Optional[bytes] = None) -> bool:
        logger.info(f"[STUB EMAIL] to={to} subject={subject}")
        return True

    async def send_whatsapp(self, to: str, body: str, attachment: Optional[bytes] = None) -> bool:
        logger.info(f"[STUB WHATSAPP] to={to} body={body[:80]}...")
        return True


# TODO(spec): Implement real providers (e.g. Twilio for SMS, SendGrid for email, Meta Business API for WhatsApp)
# Each provider should read its credentials from settings and implement the interface above.


class SMTPEmailProvider(NotificationProvider):
    """Email via SMTP. SMS and WhatsApp fall back to stub."""

    async def send_sms(self, to: str, body: str) -> bool:
        logger.warning(f"SMTP provider cannot send SMS to {to}")
        return False

    async def send_email(self, to: str, subject: str, body: str, attachment: Optional[bytes] = None) -> bool:
        import smtplib
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart
        from email.mime.application import MIMEApplication

        try:
            msg = MIMEMultipart()
            msg["From"] = settings.email_from_address
            msg["To"] = to
            msg["Subject"] = subject
            msg.attach(MIMEText(body, "html"))

            if attachment:
                part = MIMEApplication(attachment, Name="receipt.pdf")
                part["Content-Disposition"] = 'attachment; filename="receipt.pdf"'
                msg.attach(part)

            def _send():
                with smtplib.SMTP(settings.email_smtp_host, settings.email_smtp_port) as server:
                    server.starttls()
                    server.login(settings.email_smtp_user, settings.email_smtp_password)
                    server.send_message(msg)

            await asyncio.to_thread(_send)
            return True
        except Exception as e:
            logger.error(f"Email send failed to {to}: {e}")
            return False

    async def send_whatsapp(self, to: str, body: str, attachment: Optional[bytes] = None) -> bool:
        logger.warning(f"SMTP provider cannot send WhatsApp to {to}")
        return False


def get_notification_provider() -> NotificationProvider:
    """Factory — returns the configured provider."""
    if settings.email_provider == "smtp" and settings.email_smtp_host:
        return SMTPEmailProvider()
    return StubProvider()


# Send queue with retries
_send_queue: asyncio.Queue = asyncio.Queue()


async def enqueue_notification(
    channel: str,
    to: str,
    body: str,
    subject: Optional[str] = None,
    attachment: Optional[bytes] = None,
    receipt_id: Optional[int] = None,
    account_id: Optional[int] = None,
):
    """Add a notification to the send queue."""
    await _send_queue.put({
        "channel": channel,
        "to": to,
        "body": body,
        "subject": subject,
        "attachment": attachment,
        "receipt_id": receipt_id,
        "account_id": account_id,
    })


async def process_notification_queue(db_session_factory, max_retries: int = 3):
    """Background worker that processes the notification queue."""
    provider = get_notification_provider()

    while True:
        try:
            item = await asyncio.wait_for(_send_queue.get(), timeout=5.0)
        except asyncio.TimeoutError:
            continue

        channel = item["channel"]
        to = item["to"]
        success = False

        for attempt in range(1, max_retries + 1):
            try:
                if channel == "sms":
                    success = await provider.send_sms(to, item["body"])
                elif channel == "email":
                    success = await provider.send_email(to, item.get("subject", "Aqua Athletic Receipt"), item["body"], item.get("attachment"))
                elif channel == "whatsapp":
                    success = await provider.send_whatsapp(to, item["body"], item.get("attachment"))

                if success:
                    break
            except Exception as e:
                logger.error(f"Notification attempt {attempt} failed ({channel} to {to}): {e}")
                if attempt < max_retries:
                    await asyncio.sleep(2 ** attempt)

        # Log to DB
        try:
            async with db_session_factory() as session:
                from app.models.notification_log import NotificationLog
                log_entry = NotificationLog(
                    receipt_id=item.get("receipt_id"),
                    account_id=item.get("account_id"),
                    channel=channel,
                    to=to,
                    status="sent" if success else "failed",
                    error=None if success else "max retries exceeded",
                    attempts=max_retries if not success else 1,
                )
                session.add(log_entry)
                await session.commit()
        except Exception as e:
            logger.error(f"Failed to log notification: {e}")

        _send_queue.task_done()
