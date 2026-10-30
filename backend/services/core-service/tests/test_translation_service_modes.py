"""Vérifie le routage entre le modèle NLLB de base et l'adaptateur Mooré.

Un seul modèle est chargé en mémoire, avec l'adaptateur Mooré greffé dessus et
activé ou désactivé selon la langue demandée (voir `translation_service.py`).
C'est efficace en mémoire, mais fragile d'un point de vue logique : si
l'adaptateur restait activé après une requête Mooré, TOUTES les traductions
suivantes entre langues internationales passeraient par un modèle spécialisé
pour le Mooré — sans la moindre erreur, juste des traductions subtilement
dégradées, exactement le genre de régression que personne ne remarque avant
qu'un utilisateur ne s'en plaigne.

Les vrais modèles ne sont jamais chargés ici (plusieurs Go, plusieurs minutes) :
on remplace la génération par une fonction qui note simplement DANS QUEL MODE
elle a été appelée. Ce sont les décisions de routage qu'on teste, pas la
qualité des traductions — celle-ci se valide à la main (voir le journal)."""

import threading
from contextlib import contextmanager

import pytest

from app.translation_service import TranslationService


class _RecordingService(TranslationService):
    """Enregistre la suite des étapes réellement effectuées, sans aucun modèle."""

    def __init__(self, cache_size: int = 0):
        # Cache désactivé par défaut ici : ces tests observent les ÉTAPES
        # réellement exécutées, et un cache les ferait disparaître dès la
        # deuxième traduction identique. Le cache a ses propres tests.
        super().__init__(cache_size=cache_size)
        self.steps: list[tuple[str, str, bool]] = []
        self._model = object()  # fait passer `is_loaded` à vrai
        self.adapter_attached_count = 0

    def _attach_moore_adapter(self):
        # Compte les greffes : elle ne doit avoir lieu QU'UNE FOIS, quel que
        # soit le nombre de requêtes Mooré (sinon on rechargerait un modèle à
        # chaque traduction).
        if not self._adapter_attached:
            self.adapter_attached_count += 1
            self._adapter_attached = True

    @contextmanager
    def _generating(self, *, use_moore_adapter: bool):
        with self._generation_lock:
            if use_moore_adapter:
                self._attach_moore_adapter()
            yield use_moore_adapter

    def _translate_one_hop(self, text, source_lang, target_lang, *, use_moore_adapter):
        with self._generating(use_moore_adapter=use_moore_adapter):
            self.steps.append((source_lang, target_lang, use_moore_adapter))
        return f"{text}|{source_lang}->{target_lang}"


@pytest.fixture
def service():
    return _RecordingService()


def test_international_pair_never_uses_the_moore_adapter(service):
    service.translate("Bonjour", "fr", "en")
    assert service.steps == [("fr", "en", False)]
    assert service.adapter_attached_count == 0


def test_english_to_moore_is_direct_and_uses_the_adapter(service):
    """Le corpus de fine-tuning est anglais-mooré : ce couple-là n'a pas besoin
    de passer par une langue pivot."""
    service.translate("Good morning", "en", "mos")
    assert service.steps == [("en", "mos", True)]


def test_moore_to_english_is_direct_and_uses_the_adapter(service):
    service.translate("Ne y yibeoogo", "mos", "en")
    assert service.steps == [("mos", "en", True)]


def test_french_to_moore_pivots_through_english(service):
    """français -> mooré n'existe pas dans le modèle fine-tuné : on passe par
    l'anglais, avec le modèle de BASE pour la première étape et l'adaptateur
    pour la seconde."""
    service.translate("Bonjour", "fr", "mos")
    assert service.steps == [("fr", "en", False), ("en", "mos", True)]


def test_moore_to_french_pivots_through_english(service):
    service.translate("Ne y yibeoogo", "mos", "fr")
    assert service.steps == [("mos", "en", True), ("en", "fr", False)]


def test_the_adapter_is_switched_off_again_after_a_moore_translation(service):
    """LE test qui compte : une traduction Mooré ne doit pas contaminer les
    suivantes."""
    service.translate("Bonjour", "fr", "mos")
    service.steps.clear()

    service.translate("Bonjour", "fr", "en")
    assert service.steps == [("fr", "en", False)]


def test_the_adapter_is_attached_only_once(service):
    for _ in range(5):
        service.translate("Bonjour", "en", "mos")
    assert service.adapter_attached_count == 1


def test_identical_languages_short_circuit(service):
    assert service.translate("Bonjour", "fr", "fr") == "Bonjour"
    assert service.steps == []


def test_concurrent_translations_do_not_interleave_their_steps(service):
    """Le verrou sérialise la génération. Une traduction pivot fait DEUX étapes
    qui doivent rester consécutives : si une autre requête pouvait s'intercaler
    entre les deux, elle changerait le mode de l'unique modèle partagé au beau
    milieu d'une traduction."""
    threads = [threading.Thread(target=service.translate, args=("Bonjour", "fr", "mos")) for _ in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    # 4 traductions pivot = 4 paires (fr->en base, en->mos adaptateur), et
    # chaque paire doit apparaître groupée, jamais entrelacée.
    assert len(service.steps) == 8
    for index in range(0, 8, 2):
        assert service.steps[index] == ("fr", "en", False)
        assert service.steps[index + 1] == ("en", "mos", True)
