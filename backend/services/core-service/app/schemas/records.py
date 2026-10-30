"""Schémas de la sauvegarde chiffrée du carnet de santé (module 2)."""

from pydantic import BaseModel, Field

from app.schemas.common import Timestamp


class BackupIn(BaseModel):
    """Blob chiffré SUR L'APPAREIL. Le serveur ne fait que le stocker : il
    vérifie seulement que les champs binaires sont du base64 valide et que le
    chiffré ne dépasse pas MAX_BACKUP_BYTES."""

    ciphertext: str
    nonce: str = Field(max_length=200)
    salt: str = Field(max_length=200)
    kdf: str = Field(max_length=40)
    kdf_iterations: int = Field(ge=1)
    cipher: str = Field(max_length=40)
    schema_version: int = Field(ge=1)
    client_updated_at: Timestamp


class BackupOut(BackupIn):
    updated_at: Timestamp


class BackupPutResponse(BaseModel):
    updated_at: Timestamp
    size_bytes: int
