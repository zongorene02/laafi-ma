"""
Données de départ — UNIQUEMENT des données SOURCÉES.

    python -m app.seed

Ce script n'invente RIEN : pas de district, pas de numéro de téléphone non
sourcé, et aucune phrase de santé sans source publique citée. Il crée :

1. Le numéro vert national contre les violences basées sur le genre
   (80 00 12 87), avec sa source ; `verified_at` reste vide tant que l'équipe
   ne l'a pas rappelé pour confirmer qu'il est toujours en service en 2026.
2. Les numéros d'urgence nationaux : police (17), gendarmerie (16) et
   sapeurs-pompiers (18), avec leur source ; `verified_at` vide, eux aussi,
   tant que l'équipe ne les a pas appelés depuis le Burkina.
3. Les signes de danger de la grossesse et du bébé, avec le statut `sourced`.
   Ces listes viennent de l'édition 2003 du guide OMS « Pregnancy, Childbirth,
   Postpartum and Newborn Care ».
4. Les réponses de santé et les capsules de `app/seed_content.py` (OMS,
   UNFPA), avec le statut `sourced` elles aussi.

Le contenu `sourced` n'a été relu par AUCUNE sage-femme. Il n'est servi que si
SERVE_SOURCED_CONTENT=true, signalé `provisional: true`, jusqu'à sa validation
dans la console. Tout est en français seulement ; les textes mooré et dioula
restent vides, à traduire puis relire par des locuteurs natifs.

Idempotent : chaque ligne porte une clé `seed_key` stable ; une ligne déjà
présente (même modifiée depuis par l'équipe) n'est jamais dupliquée ni
écrasée.
"""

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import SessionLocal
from app.db_models import STATUS_SOURCED, Capsule, DangerSign, HelpService, KbEntry
from app.seed_content import CAPSULES, KB_ENTRIES, WHO_NEWBORN, WHO_PCPNC

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

# Liste des signes de danger de la grossesse : édition 2003 du guide OMS, ce
# que la référence `WHO_PCPNC` indique elle-même.
PREGNANCY_DANGER_SOURCE = WHO_PCPNC

ADVICE_GO_NOW = "Allez tout de suite au centre de santé, de jour comme de nuit, sans attendre."
ADVICE_FEVER = (
    "Allez au centre de santé le plus vite possible, sans attendre que ça passe. "
    "Si vous êtes trop faible pour vous lever, allez-y tout de suite."
)
ADVICE_SWELLING = "Allez au centre de santé le plus vite possible, sans attendre que ça passe."
# Le délai de 6 heures du guide ne vaut que pour un accouchement à domicile
# sans soignant : il ne doit pas apparaître ici.
ADVICE_WATERS = (
    "Allez au centre de santé dès que les eaux ont coulé, même sans contractions. N'attendez pas que l'eau s'arrête."
)
DANGER_SIGN_REFER_WHEN = "Orienter tout de suite vers le centre de santé."

# (clé stable, libellé français, conseil, mots-clés français). Les mots-clés
# sont comparés au texte NORMALISÉ (minuscules, sans accents) comme mots ou
# expressions entiers — voir app/matching.py. Ils sont à revoir par la
# sage-femme référente avant validation, comme le reste.
PREGNANCY_DANGER_SIGNS: list[tuple[str, str, str, list[str]]] = [
    (
        "grossesse-saignement",
        "Saignement pendant la grossesse",
        ADVICE_GO_NOW,
        ["saigne", "saignement", "saignements", "saigner", "sang", "hémorragie", "perte de sang", "pertes de sang"],
    ),
    (
        "grossesse-fievre",
        "Fièvre",
        ADVICE_FEVER,
        ["fièvre", "forte fièvre", "corps chaud", "j'ai chaud au corps"],
    ),
    (
        "grossesse-maux-de-tete",
        "Maux de tête violents",
        ADVICE_GO_NOW,
        ["mal de tête", "maux de tête", "mal à la tête", "migraine", "céphalée", "tête qui fait mal"],
    ),
    (
        "grossesse-vision-trouble",
        "Vision trouble",
        ADVICE_GO_NOW,
        ["vision trouble", "vision floue", "vue trouble", "vue floue", "je vois flou", "je vois trouble"],
    ),
    (
        "grossesse-convulsions",
        "Convulsions",
        ADVICE_GO_NOW,
        ["convulsion", "convulsions", "convulse", "crise convulsive", "crises convulsives"],
    ),
    (
        "grossesse-bebe-ne-bouge-plus",
        "Le bébé ne bouge plus",
        ADVICE_GO_NOW,
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
        "Perte des eaux",
        ADVICE_WATERS,
        ["perte des eaux", "perdu les eaux", "poche des eaux", "les eaux ont coulé", "liquide qui coule"],
    ),
    (
        "grossesse-douleurs-ventre",
        "Douleurs violentes au ventre",
        ADVICE_GO_NOW,
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
        ADVICE_GO_NOW,
        ["difficulté à respirer", "du mal à respirer", "respire mal", "essoufflée", "essoufflement", "souffle court"],
    ),
    (
        "grossesse-gonflement",
        "Gonflement du visage ou des mains",
        ADVICE_SWELLING,
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

BABY_DANGER_SIGNS: list[tuple[str, str, str, list[str]]] = [
    (
        "bebe-ne-tete-pas",
        "Le bébé n'arrive pas à téter",
        ADVICE_GO_NOW,
        ["ne tète pas", "ne tète plus", "refuse le sein", "n'arrive pas à téter"],
    ),
    (
        "bebe-corps-froid",
        "Le bébé a le corps froid",
        ADVICE_GO_NOW,
        ["bébé froid", "corps froid"],
    ),
    (
        "bebe-bouge-moins",
        "Le bébé bouge beaucoup moins",
        ADVICE_GO_NOW,
        ["bébé ne réagit plus", "bébé très mou", "bébé bouge peu"],
    ),
]


def _danger_sign(seed_key: str, label: str, advice: str, keywords: list[str], source: str) -> DangerSign:
    return DangerSign(
        seed_key=seed_key,
        status=STATUS_SOURCED,
        translations={
            "fr": {"label": label, "advice": advice, "agent_questions": [], "refer_when": DANGER_SIGN_REFER_WHEN}
        },
        keywords_fr=keywords,
        source=source,
    )


def _kb_entry(item: dict[str, Any]) -> KbEntry:
    # Même forme qu'une entrée créée dans la console : sinon un « Enregistrer »
    # sans aucun changement serait vu comme une modification (routers/kb.py)
    # et renverrait l'entrée en brouillon.
    translations = {
        lang: {**text, "audio_file": None, "machine_translated": False} for lang, text in item["translations"].items()
    }
    return KbEntry(
        seed_key=item["seed_key"],
        status=STATUS_SOURCED,
        topic=item["topic"],
        is_danger_topic=item["is_danger_topic"],
        translations=translations,
        source=item["source"],
    )


def _capsule(item: dict[str, Any]) -> Capsule:
    # Même remarque que pour `_kb_entry` (routers/learn.py).
    translations = {lang: {**text, "audio_file": None} for lang, text in item["translations"].items()}
    return Capsule(
        seed_key=item["seed_key"],
        status=STATUS_SOURCED,
        track=item["track"],
        order=item["order"],
        translations=translations,
        quiz=item["quiz"],
    )


def _refresh_sourced_entry(row: KbEntry, fresh: KbEntry) -> None:
    """Met à jour une fiche `sourced` : personne ne l'a touchée, car toute
    modification la repasse en brouillon. Une correction de `seed_content.py`
    atteint ainsi une base déjà remplie."""
    if row.status == STATUS_SOURCED:
        row.topic = fresh.topic
        row.is_danger_topic = fresh.is_danger_topic
        row.translations = fresh.translations
        row.source = fresh.source


def seed(db: Session) -> dict[str, int]:
    """Insère ce qui manque. Renvoie le nombre de lignes créées par table."""
    created = {"help_services": 0, "danger_signs": 0, "kb_entries": 0, "capsules": 0}

    existing_services = set(db.scalars(select(HelpService.seed_key).where(HelpService.seed_key.is_not(None))))
    for service in [GBV_HOTLINE, *EMERGENCY_NUMBERS]:
        if service["seed_key"] not in existing_services:
            db.add(HelpService(**service))
            created["help_services"] += 1

    existing_signs = set(db.scalars(select(DangerSign.seed_key).where(DangerSign.seed_key.is_not(None))))
    for signs, source in ((PREGNANCY_DANGER_SIGNS, PREGNANCY_DANGER_SOURCE), (BABY_DANGER_SIGNS, WHO_NEWBORN)):
        for seed_key, label, advice, keywords in signs:
            if seed_key not in existing_signs:
                db.add(_danger_sign(seed_key, label, advice, keywords, source))
                created["danger_signs"] += 1

    existing_entries = {row.seed_key: row for row in db.scalars(select(KbEntry).where(KbEntry.seed_key.is_not(None)))}
    for item in KB_ENTRIES:
        existing = existing_entries.get(item["seed_key"])
        if existing is None:
            db.add(_kb_entry(item))
            created["kb_entries"] += 1
        else:
            _refresh_sourced_entry(existing, _kb_entry(item))

    existing_capsules = set(db.scalars(select(Capsule.seed_key).where(Capsule.seed_key.is_not(None))))
    for item in CAPSULES:
        if item["seed_key"] not in existing_capsules:
            db.add(_capsule(item))
            created["capsules"] += 1

    db.commit()
    return created


def main() -> int:
    with SessionLocal() as db:
        created = seed(db)
    print(
        f"Seed terminé : {created['help_services']} service(s) d'aide, "
        f"{created['danger_signs']} signe(s) de danger, {created['kb_entries']} réponse(s), "
        f"{created['capsules']} capsule(s) ajoutés (statut « sourced », non relus par une sage-femme)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
