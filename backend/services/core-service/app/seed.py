"""
Données de départ — UNIQUEMENT des données SOURCÉES.

    python -m app.seed

Ce script n'invente RIEN : pas de réponse de santé, pas de capsule, pas de
district, pas de numéro de téléphone non sourcé. Tout cela doit venir plus
tard de sources réelles, validées par des professionnels. Il crée seulement :

1. Le numéro vert national contre les violences basées sur le genre
   (80 00 12 87), avec sa source ; `verified_at` reste vide tant que l'équipe
   ne l'a pas rappelé pour confirmer qu'il est toujours en service en 2026.
2. Les numéros d'urgence nationaux : police (17), gendarmerie (16) et
   sapeurs-pompiers (18), avec leur source ; `verified_at` vide, eux aussi,
   tant que l'équipe ne les a pas appelés depuis le Burkina.
3. Les signes de danger pendant la grossesse de la liste OMS, en BROUILLON :
   ils ne sont jamais servis tant qu'une sage-femme ne les a pas validés.
   Libellés, conseil et mots-clés en français seulement ; les textes mooré
   et dioula restent vides, à traduire puis relire par des locuteurs natifs.

Idempotent : chaque ligne porte une clé `seed_key` stable ; une ligne déjà
présente (même modifiée depuis par l'équipe) n'est jamais dupliquée ni
écrasée.
"""

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import SessionLocal
from app.db_models import STATUS_DRAFT, DangerSign, HelpService

GBV_HOTLINE: dict[str, Any] = {
    "seed_key": "hotline-vbg-80001287",
    "name": "Numéro vert national contre les violences basées sur le genre",
    "category": "hotline",
    "phone": "80 00 12 87",
    "city": None,
    "region": None,
    "address": None,
    # Gratuit, anonyme, 24h/24 et 7j/7 selon l'annonce du lancement
    # (2 mars 2021, ministère en charge de la Femme).
    "hours": "24h/24, 7j/7 — gratuit et anonyme",
    "free_call": True,
    # Langues de réponse non précisées par la source : laissé vide plutôt
    # que deviné.
    "languages": [],
    "source_url": (
        "https://www.burkina24.com/2021/03/02/"
        "burkina-faso-un-numero-vert-pour-lutter-contre-les-violences-basees-sur-le-genre/"
    ),
    # Pas encore confirmé en 2026 : l'app l'affiche comme tel.
    "verified_at": None,
    "active": True,
}

# Numéros d'urgence nationaux. Source : page officielle du SPF Affaires
# étrangères belge (conseils aux voyageurs, Burkina Faso, mise à jour du
# 20 octobre 2026), qui liste « Gendarmerie: 16 », « Police: 17 »,
# « Pompiers: 18 » (et 1010, non repris ici : non demandé par le dossier).
# Le site du gouvernement canadien (voyage.gc.ca) donne aussi 17 et 18.
# Gratuité, horaires et langues : non précisés par la source, donc laissés
# vides (`free_call` à False = « non confirmé », pas « payant »).
EMERGENCY_NUMBERS_SOURCE = (
    "https://diplomatie.belgium.be/fr/pays/burkina-faso/voyager-au-burkina-faso-conseils-aux-voyageurs/"
    "securite-generale-au-burkina-faso"
)


def _emergency_number(seed_key: str, name: str, category: str, phone: str) -> dict[str, Any]:
    return {
        "seed_key": seed_key,
        "name": name,
        "category": category,
        "phone": phone,
        "city": None,
        "region": None,
        "address": None,
        "hours": None,
        "free_call": False,
        "languages": [],
        "source_url": EMERGENCY_NUMBERS_SOURCE,
        "verified_at": None,
        "active": True,
    }


EMERGENCY_NUMBERS: list[dict[str, Any]] = [
    _emergency_number("urgence-police-17", "Police — numéro d'urgence", "police", "17"),
    _emergency_number("urgence-gendarmerie-16", "Gendarmerie — numéro d'urgence", "gendarmerie", "16"),
    _emergency_number("urgence-pompiers-18", "Sapeurs-pompiers — numéro d'urgence", "emergency", "18"),
]

DANGER_SIGN_SOURCE = "Liste OMS des signes de danger pendant la grossesse — à valider par la sage-femme référente"
DANGER_SIGN_ADVICE = "Allez immédiatement au centre de santé."

# (clé stable, libellé français, mots-clés français). Les mots-clés sont
# comparés au texte NORMALISÉ (minuscules, sans accents) comme mots ou
# expressions entiers — voir app/matching.py. Ils sont à revoir par la
# sage-femme référente avant validation, comme le reste.
PREGNANCY_DANGER_SIGNS: list[tuple[str, str, list[str]]] = [
    (
        "grossesse-saignement",
        "Saignement pendant la grossesse",
        ["saigne", "saignement", "saignements", "saigner", "sang", "hémorragie", "perte de sang", "pertes de sang"],
    ),
    (
        "grossesse-fievre",
        "Fièvre",
        ["fièvre", "forte fièvre", "corps chaud", "j'ai chaud au corps"],
    ),
    (
        "grossesse-maux-de-tete",
        "Maux de tête violents",
        ["mal de tête", "maux de tête", "mal à la tête", "migraine", "céphalée", "tête qui fait mal"],
    ),
    (
        "grossesse-vision-trouble",
        "Vision trouble",
        ["vision trouble", "vision floue", "vue trouble", "vue floue", "je vois flou", "je vois trouble"],
    ),
    (
        "grossesse-convulsions",
        "Convulsions",
        ["convulsion", "convulsions", "convulse", "crise convulsive", "crises convulsives"],
    ),
    (
        "grossesse-bebe-ne-bouge-plus",
        "Le bébé ne bouge plus",
        [
            "bébé ne bouge plus",
            "bébé ne bouge pas",
            "bébé bouge moins",
            "enfant ne bouge plus",
            "ne sens plus le bébé",
            "ne sens plus bouger",
        ],
    ),
    (
        "grossesse-perte-des-eaux",
        "Perte des eaux avant le terme",
        ["perte des eaux", "perdu les eaux", "poche des eaux", "les eaux ont coulé", "liquide qui coule"],
    ),
    (
        "grossesse-douleurs-ventre",
        "Douleurs violentes au ventre",
        [
            "mal au ventre",
            "douleur au ventre",
            "douleurs au ventre",
            "ventre me fait mal",
            "douleur abdominale",
            "douleurs abdominales",
        ],
    ),
    (
        "grossesse-difficulte-respirer",
        "Difficulté à respirer",
        ["difficulté à respirer", "du mal à respirer", "respire mal", "essoufflée", "essoufflement", "souffle court"],
    ),
    (
        "grossesse-gonflement",
        "Gonflement du visage ou des mains",
        [
            "visage gonflé",
            "mains gonflées",
            "visage enflé",
            "mains enflées",
            "gonflement du visage",
            "gonflement des mains",
            "œdème",
        ],
    ),
]


def seed(db: Session) -> dict[str, int]:
    """Insère ce qui manque. Renvoie le nombre de lignes créées par table."""
    created = {"help_services": 0, "danger_signs": 0}

    existing_services = set(db.scalars(select(HelpService.seed_key).where(HelpService.seed_key.is_not(None))))
    for service in [GBV_HOTLINE, *EMERGENCY_NUMBERS]:
        if service["seed_key"] not in existing_services:
            db.add(HelpService(**service))
            created["help_services"] += 1

    existing_keys = set(db.scalars(select(DangerSign.seed_key).where(DangerSign.seed_key.is_not(None))))
    for seed_key, label, keywords in PREGNANCY_DANGER_SIGNS:
        if seed_key in existing_keys:
            continue
        db.add(
            DangerSign(
                seed_key=seed_key,
                status=STATUS_DRAFT,
                translations={"fr": {"label": label, "advice": DANGER_SIGN_ADVICE}},
                keywords_fr=keywords,
                source=DANGER_SIGN_SOURCE,
            )
        )
        created["danger_signs"] += 1

    db.commit()
    return created


def main() -> int:
    with SessionLocal() as db:
        created = seed(db)
    print(
        f"Seed terminé : {created['help_services']} service(s) d'aide, "
        f"{created['danger_signs']} signe(s) de danger (brouillons) ajoutés."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
