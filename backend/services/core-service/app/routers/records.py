"""
Sauvegarde chiffrée du carnet de santé (module 2) — rôle `woman`.

Le serveur ne voit JAMAIS le carnet en clair (règle de confidentialité n°1) :
l'app dérive une clé (PBKDF2) d'une phrase secrète choisie par la femme,
chiffre le carnet (AES-256-GCM) sur le téléphone, et n'envoie que le
résultat. Le serveur stocke ce blob TEL QUEL, sans tenter de l'interpréter :
il vérifie seulement que c'est du base64 et que la taille est raisonnable.
"""

import base64
import binascii

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.auth import require_roles
from app.config import settings
from app.db import get_db
from app.db_models import ROLE_WOMAN, RecordBackup, User
from app.db_types import utc_now
from app.schemas.records import BackupIn, BackupOut, BackupPutResponse

router = APIRouter(prefix="/records", tags=["Carnet de santé"])

require_woman = require_roles(ROLE_WOMAN)


def _decoded_length(value: str, field: str) -> int:
    try:
        return len(base64.b64decode(value, validate=True))
    except (binascii.Error, ValueError) as e:
        raise HTTPException(status_code=422, detail=f"{field} : base64 invalide") from e


@router.put("/backup", response_model=BackupPutResponse)
def put_backup(
    payload: BackupIn,
    current_user: User = Depends(require_woman),
    db: Session = Depends(get_db),
) -> BackupPutResponse:
    limit = settings.max_backup_bytes
    # Refus AVANT décodage si la chaîne base64 est déjà trop longue (4
    # caractères base64 = 3 octets) : inutile de décoder 50 Mo pour les jeter.
    if len(payload.ciphertext) > (limit // 3 + 1) * 4:
        raise HTTPException(status_code=413, detail="Sauvegarde trop volumineuse")
    size_bytes = _decoded_length(payload.ciphertext, "ciphertext")
    if size_bytes > limit:
        raise HTTPException(status_code=413, detail="Sauvegarde trop volumineuse")
    _decoded_length(payload.nonce, "nonce")
    _decoded_length(payload.salt, "salt")

    now = utc_now()
    backup = db.get(RecordBackup, current_user.id)
    if backup is None:
        backup = RecordBackup(user_id=current_user.id)
        db.add(backup)
    backup.ciphertext = payload.ciphertext
    backup.nonce = payload.nonce
    backup.salt = payload.salt
    backup.kdf = payload.kdf
    backup.kdf_iterations = payload.kdf_iterations
    backup.cipher = payload.cipher
    backup.schema_version = payload.schema_version
    backup.client_updated_at = payload.client_updated_at
    backup.size_bytes = size_bytes
    backup.updated_at = now
    db.commit()
    return BackupPutResponse(updated_at=now, size_bytes=size_bytes)


@router.get("/backup", response_model=BackupOut)
def get_backup(current_user: User = Depends(require_woman), db: Session = Depends(get_db)) -> BackupOut:
    backup = db.get(RecordBackup, current_user.id)
    if backup is None:
        raise HTTPException(status_code=404, detail="Aucune sauvegarde")
    return BackupOut(
        ciphertext=backup.ciphertext,
        nonce=backup.nonce,
        salt=backup.salt,
        kdf=backup.kdf,
        kdf_iterations=backup.kdf_iterations,
        cipher=backup.cipher,
        schema_version=backup.schema_version,
        client_updated_at=backup.client_updated_at,
        updated_at=backup.updated_at,
    )


@router.delete("/backup", status_code=204)
def delete_backup(current_user: User = Depends(require_woman), db: Session = Depends(get_db)) -> Response:
    backup = db.get(RecordBackup, current_user.id)
    if backup is not None:
        db.delete(backup)
        db.commit()
    return Response(status_code=204)
