"""
Rapprochement d'une question avec la base de connaissances validée, et
détection des signes de danger — en pur Python, sur processeur, sans modèle.

Pourquoi pas un modèle d'embeddings : la machine cible a 8 Go de RAM déjà
occupés par NLLB/Whisper/MMS, et la base de connaissances compte quelques
centaines d'entrées au plus. Une similarité cosinus TF-IDF sur des n-grammes
de caractères suffit largement à ce volume, se calcule en quelques
millisecondes, et tolère bien les fautes de frappe et les variantes de
conjugaison ("saigne" / "saignement") — fréquentes dans un texte issu de la
reconnaissance vocale ou d'une traduction automatique.

Toute la comparaison se fait en FRANÇAIS normalisé : une question en mooré
ou en dioula est d'abord traduite en français (voir routers/assistant.py),
puis rapprochée des questions françaises validées (+ leurs variantes).
"""

import math
import re
import unicodedata
from collections import Counter
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

# Mots vides français (articles, pronoms, auxiliaires, mots interrogatifs
# courants) : ils n'aident pas à distinguer deux questions de santé et
# gonflent artificiellement la similarité entre questions sans rapport.
# Écrits SANS accents : la normalisation les retire avant la comparaison.
FRENCH_STOP_WORDS = frozenset(
    # Une chaîne découpée plutôt qu'une liste littérale : 130 mots restent
    # lisibles sur quelques lignes, au lieu d'une ligne par mot.
    """
    a ai aie aient aies ait alors as au aucun aussi aux avec avoir avez avons ayant
    c ca ce ceci cela celle celles celui ces cet cette ceux chez comme comment
    d dans de des du donc dont
    elle elles en encore es est et etaient etais etait etant ete etes etre eu eux
    il ils j je jusqu
    l la le les leur leurs lui
    m ma mais me meme mes moi mon
    n ne ni nos notre nous
    on ont ou par pas peu peut peux pour pourquoi qu quand que quel quelle quelles quels qui quoi
    s sa sans se ses si sois soit son sont sous suis sur
    t ta te tes toi ton tous tout toute toutes tu
    un une vos votre vous y
    faire fait faut dois doit devoir
    """.split()  # noqa: SIM905
)

NGRAM_SIZE = 3


def strip_accents(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def basic_normalize(text: str) -> str:
    """Minuscules, sans accents, ponctuation remplacée par des espaces,
    espaces multiples réduits. Conserve TOUS les mots (utilisé pour la
    détection des signes de danger, où "ne bouge plus" doit rester entier)."""
    lowered = strip_accents(text.lower()).replace("œ", "oe").replace("æ", "ae")
    cleaned = re.sub(r"[^a-z0-9]+", " ", lowered)
    return " ".join(cleaned.split())


def normalize_question(text: str) -> str:
    """Normalisation de rapprochement : `basic_normalize` + retrait des mots
    vides. Si TOUS les mots sont vides (question très courte), on garde la
    version complète plutôt qu'une chaîne vide."""
    words = basic_normalize(text).split()
    kept = [w for w in words if w not in FRENCH_STOP_WORDS]
    return " ".join(kept or words)


def _char_ngrams(normalized: str) -> Counter[str]:
    """N-grammes de caractères PAR MOT, bordés d'espaces (" sa", "sai"...,
    "nt "), pour que le début et la fin d'un mot pèsent aussi."""
    grams: Counter[str] = Counter()
    for word in normalized.split():
        padded = f" {word} "
        if len(padded) <= NGRAM_SIZE:
            grams[padded] += 1
            continue
        for i in range(len(padded) - NGRAM_SIZE + 1):
            grams[padded[i : i + NGRAM_SIZE]] += 1
    return grams


@dataclass(frozen=True)
class Candidate:
    """Une formulation candidate (question canonique ou variante) d'une entrée."""

    entry_id: str
    text: str


@dataclass(frozen=True)
class MatchResult:
    entry_id: str
    confidence: float


def best_match(query: str, candidates: Sequence[Candidate]) -> MatchResult | None:
    """Renvoie l'entrée la plus proche de `query` et sa confiance (0..1),
    ou `None` s'il n'y a aucun candidat ou aucun mot exploitable.

    La confiance est le cosinus entre les vecteurs TF-IDF de n-grammes de
    caractères ; le score d'une entrée est le MEILLEUR de ses formulations
    (question canonique + variantes). L'IDF est calculé sur le corpus des
    candidats + la requête, avec lissage (`log((1+N)/(1+df)) + 1`) pour
    qu'un n-gramme présent partout garde un poids non nul.
    """
    query_grams = _char_ngrams(normalize_question(query))
    if not query_grams or not candidates:
        return None

    candidate_grams = [_char_ngrams(normalize_question(c.text)) for c in candidates]
    documents = [*candidate_grams, query_grams]
    document_frequency: Counter[str] = Counter()
    for grams in documents:
        document_frequency.update(grams.keys())
    total = len(documents)
    idf = {gram: math.log((1 + total) / (1 + df)) + 1 for gram, df in document_frequency.items()}

    def _vector(grams: Counter[str]) -> dict[str, float]:
        return {gram: count * idf[gram] for gram, count in grams.items()}

    def _norm(vector: dict[str, float]) -> float:
        return math.sqrt(sum(v * v for v in vector.values()))

    query_vector = _vector(query_grams)
    query_norm = _norm(query_vector)
    if query_norm == 0:
        return None

    best: MatchResult | None = None
    for candidate, grams in zip(candidates, candidate_grams, strict=True):
        vector = _vector(grams)
        norm = _norm(vector)
        if norm == 0:
            continue
        dot = sum(weight * vector.get(gram, 0.0) for gram, weight in query_vector.items())
        score = dot / (query_norm * norm)
        if best is None or score > best.confidence:
            best = MatchResult(entry_id=candidate.entry_id, confidence=round(min(score, 1.0), 4))
    return best


def contains_keyword(normalized_text: str, keywords: Iterable[str]) -> bool:
    """Vrai si l'un des mots-clés (normalisés de la même façon) apparaît dans
    le texte comme mot ou expression ENTIÈRE : "sang" doit détecter "du sang"
    mais pas "sangle", et "ne bouge plus" doit être trouvé tel quel."""
    padded = f" {normalized_text} "
    for keyword in keywords:
        normalized_keyword = basic_normalize(keyword)
        if normalized_keyword and f" {normalized_keyword} " in padded:
            return True
    return False
