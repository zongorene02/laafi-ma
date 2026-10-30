"""
Test de qualité "baseline" de NLLB-200 : français -> langues locales
(Mooré/Bambara/Dioula) ET langues internationales (anglais/espagnol/
arabe/chinois), pour comparer sur la même échelle.

But : mesurer, AVANT tout fine-tuning, ce que le modèle pré-entraîné sait déjà
faire. On traduit les mêmes phrases françaises vers toutes les langues cibles
et on compare. Les langues internationales servent de "témoin" : ce sont des
langues à hautes ressources (des milliards de phrases d'entraînement
disponibles), donc on s'attend à une qualité nettement meilleure et stable —
si ce n'était pas le cas, ça voudrait dire qu'il y a un bug dans le script,
pas dans les données. On lit le résultat "à l'oeil" (pas de score automatique
ici, car BLEU/chrF demandent une traduction de référence humaine qu'on n'a
pas sous la main pour l'instant).

Modèle utilisé : facebook/nllb-200-distilled-600M
  - "distilled" = version compressée d'un plus gros modèle (3.3 milliards de
    paramètres à l'origine), entraînée à imiter le grand modèle. Résultat :
    ~600 millions de paramètres, largement plus rapide sur CPU, pour une
    perte de qualité limitée. Idéal pour un premier test sans GPU.
"""

import sys
import time

from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

# La console Windows utilise par défaut l'encodage cp1252, qui ne sait pas
# représenter certains caractères spéciaux du Mooré/Bambara/Dioula (ex. "ũ").
# On force la sortie standard en UTF-8 pour éviter un crash à l'affichage.
sys.stdout.reconfigure(encoding="utf-8")

MODEL_NAME = "facebook/nllb-200-distilled-600M"

# Codes de langue NLLB (format "code-langue_Script"), confirmés dans le
# tokenizer FLORES-200 : mos_Latn = Mooré, bam_Latn = Bambara, dyu_Latn = Dioula
TARGET_LANGS = {
    "mos_Latn": "Mooré",
    "bam_Latn": "Bambara",
    "dyu_Latn": "Dioula",
    # Langues internationales "témoin" (hautes ressources) : servent de
    # comparaison. On prend volontairement des scripts différents (latin,
    # arabe, chinois) car un vrai produit de traduction ne gère pas que du
    # texte en alphabet latin.
    "eng_Latn": "Anglais",
    "spa_Latn": "Espagnol",
    "arb_Arab": "Arabe",
    "zho_Hans": "Chinois (simplifié)",
}

SOURCE_LANG = "fra_Latn"

# Phrases de test : du simple (salutation) au plus complexe (phrase à
# subordonnée), pour voir où le modèle décroche.
TEST_SENTENCES = [
    "Bonjour, comment vas-tu ?",
    "Je m'appelle Amadou et j'habite à Ouagadougou.",
    "Le marché est fermé aujourd'hui à cause de la pluie.",
    "Est-ce que tu peux m'aider à traduire ce document ?",
    "L'éducation est la clé du développement de notre pays.",
]


def main():
    print(f"Chargement du modèle {MODEL_NAME}...")
    print("(premier lancement : télécharge ~2.5 Go depuis Hugging Face, patience)")
    t0 = time.time()
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME)
    print(f"Modèle chargé en {time.time() - t0:.1f}s\n")

    tokenizer.src_lang = SOURCE_LANG
    results_path = "nllb_baseline_results.txt"
    results_file = open(results_path, "w", encoding="utf-8")

    def out(line=""):
        print(line)
        results_file.write(line + "\n")

    for lang_code, lang_name in TARGET_LANGS.items():
        out(f"\n{'=' * 60}")
        out(f"  FRANÇAIS -> {lang_name.upper()} ({lang_code})")
        out(f"{'=' * 60}")

        # forced_bos_token_id force le modèle à démarrer sa génération par
        # le "jeton" de la langue cible : c'est comme ça qu'un seul modèle
        # NLLB sait traduire vers 200 langues différentes sans être
        # ré-entraîné à chaque fois.
        forced_bos_token_id = tokenizer.convert_tokens_to_ids(lang_code)

        for sentence in TEST_SENTENCES:
            inputs = tokenizer(sentence, return_tensors="pt")
            t0 = time.time()
            output_tokens = model.generate(
                **inputs,
                forced_bos_token_id=forced_bos_token_id,
                max_length=100,
                num_beams=5,  # recherche en faisceau : explore 5 traductions
                # candidates en parallèle plutôt qu'une seule,
                # garde la meilleure au final -> meilleure qualité
            )
            translation = tokenizer.batch_decode(output_tokens, skip_special_tokens=True)[0]
            elapsed = time.time() - t0

            out(f"\n  FR : {sentence}")
            out(f"  {lang_name} : {translation}")
            out(f"  (généré en {elapsed:.2f}s)")

    results_file.close()
    print(f"\nRésultats aussi enregistrés dans {results_path}")


if __name__ == "__main__":
    main()
