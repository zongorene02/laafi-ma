"""Petits utilitaires partagés par les routeurs."""

from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session


def get_or_404[T](db: Session, model: type[T], object_id: Any, detail: str = "Introuvable") -> T:
    obj = db.get(model, object_id)
    if obj is None:
        raise HTTPException(status_code=404, detail=detail)
    return obj
