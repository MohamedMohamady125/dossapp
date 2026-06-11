from pydantic import BaseModel
from typing import Optional


class CustomerLoginRequest(BaseModel):
    login_code: str
    password: str


class AdminLoginRequest(BaseModel):
    username: str
    password: str


class ChangePasswordRequest(BaseModel):
    new_password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    must_change_password: bool = False


class RefreshRequest(BaseModel):
    refresh_token: str
