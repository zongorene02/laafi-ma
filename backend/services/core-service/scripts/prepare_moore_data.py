"""
Prépare le corpus d'entraînement pour le fine-tuning anglais<->mooré.

Combine les 3 sous-corpus Google SMOL disponibles pour le Mooré (tous
CC-BY-4.0, donc réutilisables commercialement, contrairement à la plupart des
autres ressources trouvées pour cette langue) :
- smolsent : phrases individuelles traduites professionnellement (863)
- smoldoc  : phrases issues de documents traduits (130)
- gatitos  : lexique mot-à-mot / courtes expressions (4000, on ne garde que
  la première traduction proposée par entrée pour simplifier)

Produit deux fichiers JSONL : moore_finetune_train.jsonl et
moore_finetune_val.jsonl, avec le format {"en": "...", "mos": "..."}.

Pourquoi un split train/validation : le jeu d'entraînement sert à ajuster les
poids du modèle : le jeu de validation, jamais montré pendant l'entraînement,
sert à vérifier que le modèle généralise (traduit bien des phrases qu'il n'a
jamais vues) plutôt que de simplement "mémoriser" ses exemples d'entraînement
(le piège classique du surapprentissage / overfitting).
"""

import json
import random

from huggingface_hub import hf_hub_download

random.seed(42)  # graine fixe : le split train/val est reproductible


def load_smolsent() -> list[dict]:
    """smolsent : une paire de phrases par ligne (champs "src"/"trg")."""
    path = hf_hub_download(repo_id="google/smol", filename="smolsent/en_mos.jsonl", repo_type="dataset")
    pairs = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            pairs.append({"en": entry["src"], "mos": entry["trg"]})
    return pairs


def load_smoldoc() -> list[dict]:
    """smoldoc : un DOCUMENT par ligne, avec deux listes parallèles de
    phrases ("srcs"/"trgs", une entrée de chaque liste = une phrase du
    document et sa traduction). On "aplatit" chaque document en autant de
    paires de phrases individuelles, ce qui donne bien plus d'exemples
    d'entraînement que le nombre de documents (130) ne le laissait penser."""
    path = hf_hub_download(repo_id="google/smol", filename="smoldoc/en_mos.jsonl", repo_type="dataset")
    pairs = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            for src_sentence, trg_sentence in zip(entry["srcs"], entry["trgs"], strict=True):
                pairs.append({"en": src_sentence, "mos": trg_sentence})
    return pairs


def load_gatitos() -> list[dict]:
    path = hf_hub_download(repo_id="google/smol", filename="gatitos/en_mos.jsonl", repo_type="dataset")
    pairs = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            if entry["trgs"]:  # certaines entrées n'ont aucune traduction
                pairs.append({"en": entry["src"], "mos": entry["trgs"][0]})
    return pairs


def main():
    all_pairs = load_smolsent() + load_smoldoc() + load_gatitos()

    # Déduplication : certaines paires peuvent apparaître dans plusieurs
    # sous-corpus (ex. une phrase courte présente à la fois dans smolsent et
    # gatitos).
    seen = set()
    unique_pairs = []
    for pair in all_pairs:
        en, mos = pair["en"].strip(), pair["mos"].strip()
        if not en or not mos:  # ignore les entrées vides (bruit de données)
            continue
        key = (en, mos)
        if key not in seen:
            seen.add(key)
            unique_pairs.append({"en": en, "mos": mos})

    random.shuffle(unique_pairs)

    n_val = 200
    val_pairs = unique_pairs[:n_val]
    train_pairs = unique_pairs[n_val:]

    with open("moore_finetune_train.jsonl", "w", encoding="utf-8") as f:
        for pair in train_pairs:
            f.write(json.dumps(pair, ensure_ascii=False) + "\n")

    with open("moore_finetune_val.jsonl", "w", encoding="utf-8") as f:
        for pair in val_pairs:
            f.write(json.dumps(pair, ensure_ascii=False) + "\n")

    print(f"Total après dédoublonnage : {len(unique_pairs)}")
    print(f"Entraînement : {len(train_pairs)} paires -> moore_finetune_train.jsonl")
    print(f"Validation   : {len(val_pairs)} paires -> moore_finetune_val.jsonl")


if __name__ == "__main__":
    main()
