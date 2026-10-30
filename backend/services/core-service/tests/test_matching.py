"""Rapprochement des questions et détection des mots-clés (app/matching.py),
sans base de données ni modèle."""

from app.matching import Candidate, basic_normalize, best_match, contains_keyword, normalize_question

CANDIDATES = [
    Candidate("nutrition", "Que dois-je manger pendant la grossesse ?"),
    Candidate("nutrition", "Quels aliments manger quand on est enceinte"),
    Candidate("vaccins", "Quand faut-il vacciner mon bébé ?"),
    Candidate("regles", "Pourquoi mes règles sont-elles douloureuses ?"),
]


def test_normalization_strips_case_accents_punctuation_and_stop_words():
    assert basic_normalize("  Fièvre, MAUX de tête !! ") == "fievre maux de tete"
    assert normalize_question("Qu'est-ce que je dois manger pendant ma grossesse ?") == "manger pendant grossesse"


def test_a_rephrased_question_matches_the_right_entry_with_high_confidence():
    result = best_match("qu'est ce que je dois manger pendant ma grossesse", CANDIDATES)
    assert result is not None
    assert result.entry_id == "nutrition"
    assert result.confidence >= 0.55


def test_typos_and_missing_accents_still_match():
    result = best_match("quand vacciné mon bebe", CANDIDATES)
    assert result is not None
    assert result.entry_id == "vaccins"
    assert result.confidence >= 0.55


def test_an_unrelated_question_stays_below_the_threshold():
    result = best_match("comment réparer une moto", CANDIDATES)
    assert result is None or result.confidence < 0.55


def test_no_candidate_or_empty_question_gives_no_match():
    assert best_match("manger", []) is None
    assert best_match("   ", CANDIDATES) is None


def test_keywords_match_whole_words_and_expressions_only():
    text = basic_normalize("Je saigne beaucoup et le bébé ne bouge plus")
    assert contains_keyword(text, ["saigne"])
    assert contains_keyword(text, ["bébé ne bouge plus"])
    assert not contains_keyword(text, ["sang"])  # pas de faux positif sur un fragment
    assert not contains_keyword(basic_normalize("j'ai acheté une sangle"), ["sang"])
    assert not contains_keyword(text, ["", "   "])
