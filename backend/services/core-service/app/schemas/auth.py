"""Schémas des comptes : appareil anonyme, connexion du personnel, admin."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.schemas.common import Timestamp
from app.security import NewPassword

Role = Literal["woman", "agent", "validator", "admin"]
StaffRole = Literal["agent", "validator", "admin"]


class DeviceAccountResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    account_id: str
    # Montré UNE SEULE FOIS : seule son empreinte est conservée.
    recovery_code: str


class RecoverRequest(BaseModel):
    account_id: str = Field(max_length=64)
    recovery_code: str = Field(max_length=64)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(max_length=200)


class MeResponse(BaseModel):
    id: str
    role: Role
    email: str | None
    full_name: str | None
    district_id: str | None
    active: bool
    created_at: Timestamp

    model_config = ConfigDict(from_attributes=True)


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(max_length=200)
    new_password: NewPassword


class AdminUser(MeResponse):
    """Même forme que /auth/me (dont `active`)."""


class CreateUserRequest(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=1, max_length=200)
    role: StaffRole
    district_id: str | None = None


class CreateUserResponse(BaseModel):
    user: AdminUser
    temporary_password: str


class UpdateUserRequest(BaseModel):
    """Champs tous facultatifs : seuls ceux PRÉSENTS dans le corps sont
    appliqués (`"district_id": null` explicite retire le district)."""

    role: StaffRole | None = None
    full_name: str | None = Field(default=None, min_length=1, max_length=200)
    district_id: str | None = None
    active: bool | None = None


class TemporaryPasswordResponse(BaseModel):
    temporary_password: str


class DraftValidatedCount(BaseModel):
    draft: int
    validated: int


class AdminStatsResponse(BaseModel):
    women_accounts: int
    agents: int
    validators: int
    kb: DraftValidatedCount
    capsules: DraftValidatedCount
    unanswered_open: int
    events_last_30_days: int
