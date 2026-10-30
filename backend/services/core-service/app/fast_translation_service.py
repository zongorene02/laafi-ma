"""Moteur de traduction rapide, basé sur CTranslate2 et des poids quantifiés.

Pourquoi un DEUXIÈME moteur plutôt qu'un remplacement
-----------------------------------------------------
Mesuré le 2026-09-08 sur la machine de développement (i5-6200U, 2 cœurs, sans
carte graphique), sur les mêmes phrases :

    français -> mooré     52 s  ->  2,4 s
    français -> dioula    19 s  ->  2,7 s
    français -> bambara   11 s  ->  1,7 s
    français -> anglais  7,5 s  ->  1,0 s

Le gain est décisif pour un usage de terrain. Mais ce moteur ne rend pas
exactement les mêmes phrases que `translation_service` : la quantification en
int8 modifie certaines sorties (mesuré : 2 phrases sur 3), et le changement de
moteur en modifie d'autres. Or la validation par un locuteur natif du Mooré
porte sur les sorties de `translation_service`, pas sur celles-ci.

D'où la règle appliquée ici : ce moteur est un CHOIX EXPLICITE de l'appelant,
jamais le comportement par défaut, et il est présenté comme non encore validé
linguistiquement. Voir `docs/validation_locuteur_natif.md` pour la fiche de
relecture qui permettra de trancher.

Mémoire
-------
Les modèles ne sont chargés qu'à la première requête rapide (chargement
paresseux) : sur une machine à 8 Go, faire coexister ce moteur et le moteur de
référence sans jamais s'en servir gaspillerait 1,2 Go.
"""

import threading
from collections import OrderedDict
from pathlib import Path
from typing import Any

from app.languages import to_nllb_code
from app.translation_service import DEFAULT_CACHE_SIZE, DEFAULT_NUM_BEAMS, MODEL_NAME, PIVOT_LANG

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
BASE_MODEL_DIR = MODELS_DIR / "nllb-base-int8"
MOORE_MODEL_DIR = MODELS_DIR / "nllb-moore-int8"


class FastTranslationService:
    """Même interface publique que `TranslationService`, autre moteur.

    Contrairement au moteur de référence, qui greffe un adaptateur LoRA sur un
    modèle unique, on a ici DEUX modèles distincts : CTranslate2 ne sait pas
    activer un adaptateur à la volée, donc l'adaptateur Mooré a été fusionné
    dans les poids au moment de la conversion. En int8 chacun pèse 600 Mo, soit
    moitié moins à eux deux que l'unique modèle en pleine précision.
    """

    def __init__(self, cache_size: int = DEFAULT_CACHE_SIZE, num_beams: int = DEFAULT_NUM_BEAMS):
        self._base: Any = None
        self._moore: Any = None
        self._tokenizer: Any = None
        self._load_lock = threading.Lock()
        self._cache_lock = threading.Lock()
        # Cache séparé de celui du moteur de référence : les deux ne rendent
        # pas les mêmes phrases, mélanger leurs résultats servirait une
        # traduction rapide à qui a demandé la version vérifiée.
        self._cache: OrderedDict[tuple[str, str, str], str] = OrderedDict()
        self._cache_size = max(0, cache_size)
        self.num_beams = num_beams

    @staticmethod
    def models_present() -> bool:
        """Les modèles convertis sont volumineux et non versionnés : sur un
        dépôt fraîchement cloné, ils sont absents. Le service doit alors se
        contenter du moteur de référence, sans jamais planter."""
        return (BASE_MODEL_DIR / "model.bin").exists() and (MOORE_MODEL_DIR / "model.bin").exists()

    @staticmethod
    def runtime_available() -> bool:
        try:
            import ctranslate2  # noqa: F401
        except ImportError:
            return False
        return True

    @classmethod
    def is_available(cls) -> bool:
        return cls.runtime_available() and cls.models_present()

    @property
    def is_loaded(self) -> bool:
        return self._base is not None and self._moore is not None

    def load(self) -> None:
        """Charge les deux modèles quantifiés. Appelé à la première requête."""
        if self.is_loaded:
            return
        with self._load_lock:
            if self.is_loaded:
                return
            if not self.is_available():
                raise RuntimeError(
                    "Le moteur rapide n'est pas disponible sur ce serveur : "
                    f"il faut le paquet ctranslate2 et les modèles convertis dans {MODELS_DIR}."
                )
            import ctranslate2
            from transformers import AutoTokenizer

            self._tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
            self._base = ctranslate2.Translator(str(BASE_MODEL_DIR), device="cpu", compute_type="int8")
            self._moore = ctranslate2.Translator(str(MOORE_MODEL_DIR), device="cpu", compute_type="int8")

    def _one_hop(self, translator: Any, text: str, source_lang: str, target_lang: str) -> str:
        self._tokenizer.src_lang = to_nllb_code(source_lang)
        source = self._tokenizer.convert_ids_to_tokens(self._tokenizer.encode(text))
        result = translator.translate_batch(
            [source],
            target_prefix=[[to_nllb_code(target_lang)]],
            beam_size=self.num_beams,
            # Mêmes garde-fous que le moteur de référence : sans eux, le Mooré
            # repart en boucle de répétition (voir docs/apprentissage).
            no_repeat_ngram_size=3,
            repetition_penalty=1.3,
            max_decoding_length=200,
        )
        hypothesis = result[0].hypotheses[0][1:]  # on retire le jeton de langue cible
        return str(self._tokenizer.decode(self._tokenizer.convert_tokens_to_ids(hypothesis)))

    def _cache_get(self, key: tuple[str, str, str]) -> str | None:
        if self._cache_size == 0:
            return None
        with self._cache_lock:
            if key in self._cache:
                self._cache.move_to_end(key)
                return self._cache[key]
        return None

    def _cache_put(self, key: tuple[str, str, str], value: str) -> None:
        if self._cache_size == 0:
            return
        with self._cache_lock:
            self._cache[key] = value
            self._cache.move_to_end(key)
            while len(self._cache) > self._cache_size:
                self._cache.popitem(last=False)

    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        if source_lang == target_lang:
            return text
        if not self.is_loaded:
            self.load()

        key = (source_lang, target_lang, text)
        cached = self._cache_get(key)
        if cached is not None:
            return cached

        result = self._translate_uncached(text, source_lang, target_lang)
        self._cache_put(key, result)
        return result

    def _translate_uncached(self, text: str, source_lang: str, target_lang: str) -> str:
        moore_involved = source_lang == "mos" or target_lang == "mos"
        if not moore_involved:
            return self._one_hop(self._base, text, source_lang, target_lang)

        # Même routage que le moteur de référence : le modèle spécialisé ne
        # connaît que le couple anglais <-> mooré, tout le reste passe par un
        # pivot anglais.
        if {source_lang, target_lang} == {"mos", PIVOT_LANG}:
            return self._one_hop(self._moore, text, source_lang, target_lang)
        if source_lang == "mos":
            pivot = self._one_hop(self._moore, text, "mos", PIVOT_LANG)
            return self._one_hop(self._base, pivot, PIVOT_LANG, target_lang)
        pivot = self._one_hop(self._base, text, source_lang, PIVOT_LANG)
        return self._one_hop(self._moore, pivot, PIVOT_LANG, "mos")


fast_translation_service = FastTranslationService()
