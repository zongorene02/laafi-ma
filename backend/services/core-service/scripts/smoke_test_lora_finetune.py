"""
Test de fumée (smoke test) du notebook de fine-tuning, en local sur CPU,
sur un minuscule sous-ensemble de données et seulement 2 pas d'entraînement.

But : attraper les bugs évidents (mauvais nom de paramètre, incompatibilité
d'API entre librairies...) AVANT de faire tourner le vrai entraînement sur
Colab, où corriger un bug coûte plus cher (il faut re-télécharger le modèle,
relancer le runtime...). Ce n'est PAS un test de qualité du fine-tuning (2 pas
sur 20 phrases n'apprend rien d'utile) — juste un test "est-ce que ça
s'exécute sans planter".
"""

import json
import sys

import numpy as np
import sacrebleu
from datasets import Dataset
from peft import LoraConfig, TaskType, get_peft_model
from transformers import (
    AutoModelForSeq2SeqLM,
    AutoTokenizer,
    DataCollatorForSeq2Seq,
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
)

sys.stdout.reconfigure(encoding="utf-8")

MODEL_NAME = "facebook/nllb-200-distilled-600M"
MAX_LENGTH = 64


def load_pairs(path, n):
    pairs = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            pairs.append(json.loads(line))
            if len(pairs) >= n:
                break
    return pairs


train_pairs = load_pairs("moore_finetune_train.jsonl", 20)
val_pairs = load_pairs("moore_finetune_val.jsonl", 10)
print(f"Smoke test avec {len(train_pairs)} exemples train / {len(val_pairs)} val")

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
base_model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME)

lora_config = LoraConfig(
    task_type=TaskType.SEQ_2_SEQ_LM,
    r=16,
    lora_alpha=32,
    lora_dropout=0.05,
    target_modules=["q_proj", "k_proj", "v_proj", "out_proj"],
)
model = get_peft_model(base_model, lora_config)
model.print_trainable_parameters()

train_dataset = Dataset.from_list(train_pairs)
val_dataset = Dataset.from_list(val_pairs)


def preprocess(examples):
    tokenizer.src_lang = "eng_Latn"
    model_inputs = tokenizer(examples["en"], max_length=MAX_LENGTH, truncation=True)
    tokenizer.src_lang = "mos_Latn"
    labels = tokenizer(examples["mos"], max_length=MAX_LENGTH, truncation=True)
    model_inputs["labels"] = labels["input_ids"]
    return model_inputs


train_tokenized = train_dataset.map(preprocess, batched=True, remove_columns=["en", "mos"])
val_tokenized = val_dataset.map(preprocess, batched=True, remove_columns=["en", "mos"])
print("Tokenisation OK")

data_collator = DataCollatorForSeq2Seq(tokenizer, model=model, padding=True)


def compute_metrics(eval_preds):
    predictions, labels = eval_preds
    predictions = np.where(predictions != -100, predictions, tokenizer.pad_token_id)
    labels = np.where(labels != -100, labels, tokenizer.pad_token_id)
    decoded_preds = tokenizer.batch_decode(predictions, skip_special_tokens=True)
    decoded_labels = tokenizer.batch_decode(labels, skip_special_tokens=True)
    chrf = sacrebleu.corpus_chrf(decoded_preds, [decoded_labels])
    return {"chrf": chrf.score}


training_args = Seq2SeqTrainingArguments(
    output_dir="./smoke_test_checkpoints",
    per_device_train_batch_size=2,
    per_device_eval_batch_size=2,
    learning_rate=1e-4,
    max_steps=2,
    eval_strategy="steps",
    eval_steps=2,
    save_strategy="no",
    predict_with_generate=True,
    generation_max_length=MAX_LENGTH,
    report_to="none",
)

trainer = Seq2SeqTrainer(
    model=model,
    args=training_args,
    train_dataset=train_tokenized,
    eval_dataset=val_tokenized,
    data_collator=data_collator,
    compute_metrics=compute_metrics,
)

print("Lancement de l'entraînement (2 pas seulement)...")
trainer.train()
print("\nSMOKE TEST REUSSI : le pipeline d'entraînement s'exécute sans erreur.")
