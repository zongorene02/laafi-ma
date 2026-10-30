"""
Service de traduction texte-à-texte, basé sur NLLB-200.

Pattern important ici : le modèle est chargé UNE SEULE FOIS, au démarrage du
serveur (voir main.py, fonction lifespan), et réutilisé pour toutes les
requêtes suivantes. Charger un modèle de deep learning prend plusieurs
secondes voire minutes (lecture de centaines de Mo/Go depuis le disque,
initialisation des poids en mémoire) — le refaire à chaque requête rendrait
l'API inutilisable. C'est un principe de base du "model serving" en MLOps :
séparer le coût de chargement (une fois) du coût d'inférence (par requête,
qui lui doit rester rapide).

Cas particulier du Mooré : le corpus disponible pour le fine-tuning
(Google SMOL) n'existe qu'en anglais-mooré, pas en français-mooré. Le modèle fine-tuné
(`models/moore-nllb-lora-adapter/`, produit par
`backend/notebooks/moore_finetuning_colab.ipynb`) ne sait donc bien traduire
qu'entre l'anglais et le mooré. Pour toute autre langue impliquant le mooré
(français, espagnol...), on route automatiquement la traduction PAR
l'anglais : ex. français -> mooré devient français -> anglais (modèle de
base) -> anglais -> mooré (modèle fine-tuné). L'anglais n'est jamais proposé
aux utilisatrices de Laafi Ma : c'est uniquement ce pivot interne. Cette technique s'appelle une
traduction "pivot" ou "bridge" : classique quand on manque de données
directes entre deux langues mais qu'on a de bonnes données via une langue
intermédiaire.

Un seul modèle en mémoire, deux modes : l'adaptateur LoRA Mooré (quelques
Mo) est greffé sur le modèle de base déjà chargé, et activé ou désactivé
selon la langue demandée — plutôt qu'une deuxième copie complète du modèle
(2,4 Go) comme dans une version précédente. Voir `_attach_moore_adapter`
pour la mesure qui a motivé ce changement.
"""

import threading
from collections import OrderedDict
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from app.languages import PIVOT_LANG, to_nllb_code

MODEL_NAME = "facebook/nllb-200-distilled-600M"
MOORE_ADAPTER_PATH = Path(__file__).resolve().parent.parent / "models" / "moore-nllb-lora-adapter"

# `PIVOT_LANG` est ré-exporté (fast_translation_service l'importe d'ici).
__all__ = ["DEFAULT_CACHE_SIZE", "DEFAULT_NUM_BEAMS", "MODEL_NAME", "PIVOT_LANG", "TranslationService"]

# Nombre de traductions conservées en mémoire. Une entrée pèse quelques
# centaines d'octets : 512 entrées coûtent une fraction de mégaoctet, à
# comparer aux dizaines de secondes que coûte une génération sur processeur.
DEFAULT_CACHE_SIZE = 512

# Nombre d'hypothèses explorées en parallèle par la recherche en faisceau.
# Le coût de génération est à peu près proportionnel à ce nombre : le baisser
# est le levier de latence le plus direct, mais il CHANGE les sorties. Toute
# modification doit être mesurée sur un jeu de phrases de référence avant
# d'être adoptée (voir docs/apprentissage).
DEFAULT_NUM_BEAMS = 5


class TranslationService:
    """Traduit du texte, avec un cache des traductions déjà calculées.

    Le cache est volontairement en mémoire du processus, pas dans Redis : il
    n'ajoute aucune dépendance à démarrer, et le gain visé est celui des
    phrases répétées d'un même service (formules sanitaires, administratives)
    au cours d'une session. Un cache partagé entre l'API et le worker serait
    un raffinement utile le jour où plusieurs instances tournent réellement.

    Il ne peut pas modifier une traduction : à entrée identique, il rend
    exactement ce que le modèle avait produit. C'est la seule optimisation de
    cette classe dont on soit certain qu'elle ne change aucune sortie.
    """

    def __init__(self, cache_size: int = DEFAULT_CACHE_SIZE, num_beams: int = DEFAULT_NUM_BEAMS):
        # `Any` volontaire : selon la version de transformers, le tokenizer
        # rendu par `from_pretrained` est l'un ou l'autre backend, et figer un
        # type précis ici casse la vérification à chaque montée de version.
        self._tokenizer: Any = None
        self._model: Any = None
        self._adapter_attached = False
        # Sérialise TOUTE la génération : voir `_generating`.
        self._generation_lock = threading.RLock()
        # Verrou distinct de celui de génération : on ne veut pas bloquer une
        # traduction en cours pour lire ou écrire une entrée de cache.
        self._cache_lock = threading.Lock()
        self._cache: OrderedDict[tuple[str, str, str], str] = OrderedDict()
        self._cache_size = max(0, cache_size)
        self.num_beams = num_beams
        self.cache_hits = 0
        self.cache_misses = 0

    def load(self):
        """Charge le modèle de base en mémoire. À appeler une fois au démarrage.
        L'adaptateur Mooré, lui, n'est greffé qu'à la première requête qui en a
        besoin (chargement paresseux, même logique que les modèles TTS dans
        speech_service.py).

        Import de transformers ICI et pas en tête de module : importer torch
        et transformers coûte plusieurs centaines de Mo de mémoire, à payer
        seulement si l'on charge vraiment le modèle — pas pour lancer les
        tests ou un serveur démarré sans modèles (LOAD_MODELS_ON_STARTUP=false)."""
        from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

        self._tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
        self._model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME)

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    def _attach_moore_adapter(self):
        """Greffe l'adaptateur Mooré SUR le modèle déjà chargé.

        Auparavant, on chargeait une DEUXIÈME copie complète de NLLB-200 pour
        y appliquer l'adaptateur, afin qu'une requête Mooré et une requête
        ordinaire ne se partagent jamais le même objet. C'était correct, mais
        beaucoup trop cher : deux fois 2,4 Go sur une machine qui en a 8 au
        total. Mesuré sur la machine de développement, la toute première
        traduction vers le Mooré faisait grimper le service à plus de 5 Go, il
        ne restait que ~700 Mo de libre, et la traduction — qui prend une
        vingtaine de secondes d'ordinaire — ne rendait plus la main du tout,
        le système passant son temps à échanger de la mémoire avec le disque.

        Un adaptateur LoRA ne pèse que quelques Mo : le greffer sur le modèle
        existant donne exactement le même résultat pour presque rien. Le prix
        à payer est que le modèle a désormais DEUX modes (adaptateur actif ou
        non), un état partagé — d'où la sérialisation dans `_generating`.
        """
        if self._adapter_attached:
            return
        assert self._model is not None, "Modèle non chargé — appeler load() d'abord."
        if not MOORE_ADAPTER_PATH.exists():
            raise ValueError(
                f"Le modèle Mooré fine-tuné n'est pas installé sur ce serveur (dossier attendu : {MOORE_ADAPTER_PATH})."
            )
        from peft import PeftModel

        self._model = PeftModel.from_pretrained(self._model, str(MOORE_ADAPTER_PATH))
        self._model.eval()
        self._adapter_attached = True

    @contextmanager
    def _generating(self, *, use_moore_adapter: bool):
        """Prend le verrou de génération et met le modèle dans le bon mode.

        Un seul verrou pour deux états partagés qu'on ne peut pas laisser deux
        requêtes modifier en même temps :

        1. `tokenizer.src_lang`, écrit juste avant l'encodage. Deux traductions
           simultanées pouvaient s'écraser mutuellement cette valeur entre
           l'affectation et l'encodage — et produire une traduction faite
           depuis la mauvaise langue source, sans la moindre erreur visible.
           Ce bug existait déjà avant l'ajout de l'adaptateur.
        2. L'activation de l'adaptateur Mooré, désormais portée par le modèle
           unique.

        Sérialiser n'enlève quasiment aucune performance ici : ces modèles
        tournent sur processeur et saturent déjà la machine avec une seule
        requête — deux traductions en parallèle ne vont pas plus vite, elles
        se ralentissent l'une l'autre.
        """
        with self._generation_lock:
            assert self._model is not None, "Modèle non chargé — appeler load() d'abord."
            if use_moore_adapter:
                self._attach_moore_adapter()
                yield self._model
            elif self._adapter_attached:
                # `disable_adapter()` rend temporairement au modèle son
                # comportement d'origine : indispensable, sinon toutes les
                # traductions entre langues internationales passeraient par
                # l'adaptateur Mooré dès qu'une seule requête Mooré a eu lieu.
                with self._model.disable_adapter():
                    yield self._model
            else:
                yield self._model

    def _translate_one_hop(self, text: str, source_lang: str, target_lang: str, *, use_moore_adapter: bool) -> str:
        """Une seule traduction directe (pas de pivot)."""
        assert self._tokenizer is not None, "Tokenizer non chargé — appeler load() avant translate()."

        with self._generating(use_moore_adapter=use_moore_adapter) as model:
            self._tokenizer.src_lang = to_nllb_code(source_lang)
            forced_bos_token_id = self._tokenizer.convert_tokens_to_ids(to_nllb_code(target_lang))

            inputs = self._tokenizer(text, return_tensors="pt")
            output_tokens = model.generate(
                **inputs,
                forced_bos_token_id=forced_bos_token_id,
                max_length=200,
                num_beams=self.num_beams,
                # Mitigation de la dégénérescence par répétition observée sur
                # le Mooré pendant le test baseline (voir docs/apprentissage) :
                # no_repeat_ngram_size interdit de répéter une séquence de 3
                # mots déjà générée, repetition_penalty pénalise les mots déjà
                # utilisés.
                no_repeat_ngram_size=3,
                repetition_penalty=1.3,
            )
        return self._tokenizer.batch_decode(output_tokens, skip_special_tokens=True)[0]

    def _cache_get(self, key: tuple[str, str, str]) -> str | None:
        if self._cache_size == 0:
            return None
        with self._cache_lock:
            if key in self._cache:
                self._cache.move_to_end(key)  # le plus récemment utilisé en dernier
                self.cache_hits += 1
                return self._cache[key]
        self.cache_misses += 1
        return None

    def _cache_put(self, key: tuple[str, str, str], value: str) -> None:
        if self._cache_size == 0:
            return
        with self._cache_lock:
            self._cache[key] = value
            self._cache.move_to_end(key)
            while len(self._cache) > self._cache_size:
                self._cache.popitem(last=False)  # évince la plus ancienne

    def cache_stats(self) -> dict[str, int]:
        with self._cache_lock:
            size = len(self._cache)
        return {"entries": size, "capacity": self._cache_size, "hits": self.cache_hits, "misses": self.cache_misses}

    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        if not self.is_loaded:
            raise RuntimeError("Le modèle n'est pas encore chargé (appeler load() d'abord).")
        assert self._model is not None  # garanti par is_loaded, juste pour mypy

        if source_lang == target_lang:
            return text

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
            return self._translate_one_hop(text, source_lang, target_lang, use_moore_adapter=False)

        # Cas directs : un des deux côtés est déjà l'anglais, pas besoin de pivot.
        if {source_lang, target_lang} == {"mos", PIVOT_LANG}:
            return self._translate_one_hop(text, source_lang, target_lang, use_moore_adapter=True)

        # Le verrou est réentrant (RLock) : on le prend pour TOUTE la traduction
        # pivot, pas seulement pour chacune de ses deux étapes. Sans ça, une
        # autre requête pouvait se glisser entre les deux étapes et changer le
        # mode du modèle sous nos pieds.
        with self._generation_lock:
            # Cas pivot : mooré -> [anglais fine-tuné] -> [anglais base] -> cible
            if source_lang == "mos":
                pivot_text = self._translate_one_hop(text, "mos", PIVOT_LANG, use_moore_adapter=True)
                return self._translate_one_hop(pivot_text, PIVOT_LANG, target_lang, use_moore_adapter=False)

            # Cas pivot : source -> [anglais base] -> [anglais fine-tuné] -> mooré
            pivot_text = self._translate_one_hop(text, source_lang, PIVOT_LANG, use_moore_adapter=False)
            return self._translate_one_hop(pivot_text, PIVOT_LANG, "mos", use_moore_adapter=True)


# Instance unique partagée par toute l'application (singleton).
translation_service = TranslationService()
