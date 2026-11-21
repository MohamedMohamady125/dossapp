from pydantic import BaseModel
from typing import Optional


class CustomerLoginRequest(BaseModel):
    login_code: str  # the login code, or the email the parent verified
    password: str


class AdminLoginRequest(BaseModel):
    username: str
    password: str


class ChangePasswordRequest(BaseModel):
    new_password: str


class ProfileOut(BaseModel):
    """One swimmer a parent can open."""
    account_id: int
    athlete_number: int
    name: str
    branch_id: int
    branch_name: str
    login_code: str
    is_current: bool = False


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    must_change_password: bool = False
    # Every swimmer this parent can open (one entry for a single-child family)
    profiles: list[ProfileOut] = []


class RefreshRequest(BaseModel):
    refresh_token: str


class SendVerificationRequest(BaseModel):
    email: str


class VerifyCodeRequest(BaseModel):
    email: str
    code: str


class SetPasswordWithEmailRequest(BaseModel):
    email: str
    code: str
    new_password: str


class ForgotPasswordRequest(BaseModel):
    email: str


class ForgotPasswordVerifyRequest(BaseModel):
    email: str
    code: str


class ForgotPasswordResetRequest(BaseModel):
    email: str
    code: str
    new_password: str
