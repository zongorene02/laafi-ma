"""Langues : seules fr/mos/dyu sont proposées ; l'anglais n'existe que comme
pivot interne de traduction (jamais accepté en entrée d'un endpoint)."""

import pytest

from app.languages import USER_LANGUAGES, is_user_language, to_nllb_code


def test_to_nllb_code_known_language():
    assert to_nllb_code("fr") == "fra_Latn"
    assert to_nllb_code("mos") == "mos_Latn"
    assert to_nllb_code("dyu") == "dyu_Latn"


def test_english_is_only_an_internal_pivot():
    assert to_nllb_code("en") == "eng_Latn"
    assert not is_user_language("en")


@pytest.mark.parametrize("dropped", ["bam", "es", "ar", "zh", "wolof"])
def test_languages_outside_laafi_ma_are_refused(dropped):
    assert dropped not in USER_LANGUAGES
    with pytest.raises(ValueError, match=dropped):
        to_nllb_code(dropped)


def test_languages_endpoint_lists_exactly_the_three_user_languages(client):
    response = client.get("/languages")
    assert response.status_code == 200
    assert response.json() == [
        {"code": "fr", "name": "Français"},
        {"code": "mos", "name": "Mooré"},
        {"code": "dyu", "name": "Dioula"},
    ]
