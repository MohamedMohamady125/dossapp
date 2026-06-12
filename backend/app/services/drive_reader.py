"""Google Drive file reader — downloads workbooks for parsing."""

import io
import logging
import tempfile
from typing import Optional

from app.config import settings

logger = logging.getLogger(__name__)

SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]

# Google libraries are optional (not needed for local dev with sample workbook)
try:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaIoBaseDownload
    _HAS_GOOGLE = True
except ImportError:
    _HAS_GOOGLE = False
    logger.info("Google Drive libraries not installed — Drive features disabled")


def _get_drive_service():
    """Build a Google Drive API service client."""
    if not _HAS_GOOGLE:
        raise RuntimeError("Google Drive libraries not installed")
    creds = service_account.Credentials.from_service_account_file(
        settings.google_drive_credentials_json, scopes=SCOPES
    )
    return build("drive", "v3", credentials=creds, cache_discovery=False)


def get_file_modified_time(file_id: str) -> Optional[str]:
    """Get the modifiedTime of a Drive file. Returns ISO string or None on error."""
    try:
        service = _get_drive_service()
        file_meta = service.files().get(fileId=file_id, fields="modifiedTime").execute()
        return file_meta.get("modifiedTime")
    except Exception as e:
        logger.error(f"Failed to get modifiedTime for {file_id}: {e}")
        return None


def download_file(file_id: str) -> Optional[str]:
    """Download a Drive file to a temp path. Returns the temp file path or None on error."""
    try:
        service = _get_drive_service()

        # Check mime type to decide: export (Google Sheet) vs direct download (.xlsx)
        file_meta = service.files().get(fileId=file_id, fields="mimeType").execute()
        mime = file_meta.get("mimeType", "")

        if mime == "application/vnd.google-apps.spreadsheet":
            # Google Sheet → export as xlsx
            request = service.files().export_media(
                fileId=file_id,
                mimeType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            )
        else:
            # Already an xlsx/xls file → direct download
            request = service.files().get_media(fileId=file_id)

        tmp = tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False)
        downloader = MediaIoBaseDownload(io.FileIO(tmp.name, "wb"), request)

        done = False
        while not done:
            _, done = downloader.next_chunk()

        logger.info(f"Downloaded Drive file {file_id} to {tmp.name}")
        return tmp.name
    except Exception as e:
        logger.error(f"Failed to download Drive file {file_id}: {e}")
        return None
