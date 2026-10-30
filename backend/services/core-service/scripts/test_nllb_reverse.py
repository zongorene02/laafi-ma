"""
Test de la traduction VERS le français (sens inverse du premier test).

Pourquoi c'est un test à part : en traduction automatique, la qualité n'est
pas symétrique. Traduire DEPUIS une langue à faibles ressources (le modèle
doit bien COMPRENDRE une langue mal représentée à l'entraînement) est un
problème différent de traduire VERS cette même langue (le modèle doit bien
GÉNÉRER dans cette langue). Un modèle peut être correct dans un sens et
mauvais dans l'autre. Pour une app de traduction bidirectionnelle (un
utilisateur mooré qui écrit à un utilisateur francophone, et vice versa), il
faut valider les deux sens séparément.
"""

import sys
import time

from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

sys.stdout.reconfigure(encoding="utf-8")

MODEL_NAME = "facebook/nllb-200-distilled-600M"
TARGET_LANG = "fra_Latn"

SOURCE_LANGS = {
    "mos_Latn": (
        "Mooré",
        [
            "Sũ-noog daarã, fo maanda wãn-wãna?",
            "Mam yʋʋr la Amadou, la m be Ouagadougou.",
        ],
    ),
    "bam_Latn": (
        "Bambara",
        [
            "I bɛ cogo di?",
            "Ne tɔgɔ ye ko Amadou. Ne sigilen bɛ Ouagadougou.",
        ],
    ),
    "dyu_Latn": (
        "Dioula",
        [
            "I be cogo di?",
            "N' tɔgɔ ko Amadou ani n' be sigi Ouagadougou.",
        ],
    ),
    "eng_Latn": (
        "Anglais",
        [
            "Hello, how are you?",
            "Can you help me translate this document?",
        ],
    ),
}


def main():
    print(f"Chargement du modèle {MODEL_NAME}...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME)
    print("Modèle chargé.\n")

    results_path = "nllb_reverse_results.txt"
    results_file = open(results_path, "w", encoding="utf-8")

    def out(line=""):
        print(line)
        results_file.write(line + "\n")

    forced_bos_token_id = tokenizer.convert_tokens_to_ids(TARGET_LANG)

    for lang_code, (lang_name, sentences) in SOURCE_LANGS.items():
        out(f"\n{'=' * 60}")
        out(f"  {lang_name.upper()} -> FRANÇAIS")
        out(f"{'=' * 60}")

        tokenizer.src_lang = lang_code

        for sentence in sentences:
            inputs = tokenizer(sentence, return_tensors="pt")
            t0 = time.time()
            output_tokens = model.generate(
                **inputs,
                forced_bos_token_id=forced_bos_token_id,
                max_length=200,
                num_beams=5,
                no_repeat_ngram_size=3,
                repetition_penalty=1.3,
            )
            translation = tokenizer.batch_decode(output_tokens, skip_special_tokens=True)[0]
            elapsed = time.time() - t0

            out(f"\n  {lang_name} : {sentence}")
            out(f"  Français : {translation}")
            out(f"  (généré en {elapsed:.2f}s)")

    results_file.close()
    print(f"\nRésultats enregistrés dans {results_path}")


if __name__ == "__main__":
    main()
