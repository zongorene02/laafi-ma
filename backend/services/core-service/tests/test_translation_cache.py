"""Vérifie le cache de traductions.

Une génération prend des dizaines de secondes sur processeur : retraduire une
phrase déjà traduite est le gaspillage le plus facile à supprimer. Le cache ne
doit jamais changer une sortie — à entrée identique il rend exactement ce que
le modèle avait produit — mais il doit distinguer les couples de langues, et
ne pas grossir indéfiniment.

Comme partout ailleurs dans ces tests, aucun modèle n'est chargé : on compte
les appels réellement transmis au moteur de génération.
"""

import threading

import pytest

from app.translation_service import TranslationService


class _CountingService(TranslationService):
    """Compte les traductions réellement calculées (celles qui manquent au cache)."""

    def __init__(self, cache_size: int = 8):
        super().__init__(cache_size=cache_size)
        self._model = object()  # fait passer `is_loaded` à vrai
        self.calls: list[tuple[str, str, str]] = []

    def _translate_uncached(self, text: str, source_lang: str, target_lang: str) -> str:
        self.calls.append((source_lang, target_lang, text))
        return f"[{source_lang}->{target_lang}] {text}"


@pytest.fixture
def service():
    return _CountingService()


def test_the_same_request_is_computed_once_and_reused(service):
    first = service.translate("Bonjour", "fr", "mos")
    second = service.translate("Bonjour", "fr", "mos")

    assert first == second
    assert len(service.calls) == 1, "la deuxième traduction aurait dû venir du cache"
    assert service.cache_stats()["hits"] == 1


def test_the_cache_never_alters_the_output(service):
    direct = service._translate_uncached("Bonjour", "fr", "mos")
    service.translate("Bonjour", "fr", "mos")
    from_cache = service.translate("Bonjour", "fr", "mos")

    assert from_cache == direct


def test_language_pair_is_part_of_the_key(service):
    """Même texte, cibles différentes : deux traductions distinctes, jamais
    l'une pour l'autre — la confusion la plus dangereuse que ce cache pourrait
    introduire."""
    to_moore = service.translate("Bonjour", "fr", "mos")
    to_dioula = service.translate("Bonjour", "fr", "dyu")

    assert to_moore != to_dioula
    assert len(service.calls) == 2


def test_source_language_is_part_of_the_key(service):
    service.translate("Bonjour", "fr", "en")
    service.translate("Bonjour", "dyu", "en")
    assert len(service.calls) == 2


def test_identical_languages_are_not_cached(service):
    assert service.translate("Bonjour", "fr", "fr") == "Bonjour"
    assert service.calls == []
    assert service.cache_stats()["entries"] == 0


def test_the_cache_evicts_the_least_recently_used_entry():
    service = _CountingService(cache_size=2)
    service.translate("un", "fr", "en")
    service.translate("deux", "fr", "en")
    service.translate("un", "fr", "en")  # "un" redevient le plus récent
    service.translate("trois", "fr", "en")  # évince "deux", le plus ancien

    assert service.cache_stats()["entries"] == 2
    service.calls.clear()
    service.translate("un", "fr", "en")  # toujours en cache
    assert service.calls == []
    service.translate("deux", "fr", "en")  # évincé : recalculé
    assert len(service.calls) == 1


def test_cache_can_be_disabled():
    service = _CountingService(cache_size=0)
    service.translate("Bonjour", "fr", "mos")
    service.translate("Bonjour", "fr", "mos")
    assert len(service.calls) == 2


def test_cache_is_safe_under_concurrent_access(service):
    """Plusieurs requêtes simultanées sur la même phrase ne doivent ni planter
    ni corrompre le cache. Le nombre de calculs réels n'est pas garanti (une
    course avant la première écriture est possible et sans conséquence), mais
    le résultat rendu doit être identique pour tous."""
    results: list[str] = []
    lock = threading.Lock()

    def run():
        value = service.translate("Bonjour", "fr", "mos")
        with lock:
            results.append(value)

    threads = [threading.Thread(target=run) for _ in range(8)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert len(results) == 8
    assert len(set(results)) == 1
    assert service.cache_stats()["entries"] == 1
