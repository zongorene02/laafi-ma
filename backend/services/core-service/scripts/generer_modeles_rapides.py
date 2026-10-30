"""Convertit NLLB en int8 pour CTranslate2, en deux variantes :

  - base   : le modele tel quel (toutes les langues sauf le moore)
  - moore  : le meme modele avec l'adaptateur LoRA FUSIONNE dans les poids

Deux modeles distincts sont necessaires parce que CTranslate2 ne sait pas
activer/desactiver un adaptateur a la volee comme le fait le service actuel.
En int8 chacun pese environ 600 Mo : les deux ensemble tiennent dans la moitie
de ce que coute aujourd'hui l'unique modele en pleine precision.
"""

import os
import shutil
import subprocess
import sys
import time

CORE = r"D:\liac\projet 22 IA\backend\services\core-service"
OUT_ROOT = sys.argv[1]
MODEL_NAME = "facebook/nllb-200-distilled-600M"

os.chdir(CORE)
sys.path.insert(0, CORE)
sys.stdout.reconfigure(encoding="utf-8")

from peft import PeftModel  # noqa: E402
from transformers import AutoModelForSeq2SeqLM, AutoTokenizer  # noqa: E402

from app.translation_service import MOORE_ADAPTER_PATH  # noqa: E402


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


os.makedirs(OUT_ROOT, exist_ok=True)
merged_dir = os.path.join(OUT_ROOT, "_merged_moore_fp32")
base_ct2 = os.path.join(OUT_ROOT, "nllb-base-int8")
moore_ct2 = os.path.join(OUT_ROOT, "nllb-moore-int8")

# ---------------------------------------------------------------- base
if not os.path.exists(os.path.join(base_ct2, "model.bin")):
    log("conversion du modele de base en int8...")
    t0 = time.time()
    subprocess.run(
        [
            sys.executable,
            "-m",
            "ctranslate2.converters.transformers",
            "--model",
            MODEL_NAME,
            "--output_dir",
            base_ct2,
            "--quantization",
            "int8",
            "--force",
        ],
        check=True,
    )
    log(f"base convertie en {time.time() - t0:.0f}s")
else:
    log("base deja convertie")

# ---------------------------------------------------------------- moore
if not os.path.exists(os.path.join(moore_ct2, "model.bin")):
    log("fusion de l'adaptateur LoRA dans les poids...")
    t0 = time.time()
    base = AutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME)
    merged = PeftModel.from_pretrained(base, str(MOORE_ADAPTER_PATH)).merge_and_unload()
    merged.save_pretrained(merged_dir)
    AutoTokenizer.from_pretrained(MODEL_NAME).save_pretrained(merged_dir)
    del merged, base
    log(f"fusion faite en {time.time() - t0:.0f}s")

    log("conversion de la variante moore en int8...")
    t0 = time.time()
    subprocess.run(
        [
            sys.executable,
            "-m",
            "ctranslate2.converters.transformers",
            "--model",
            merged_dir,
            "--output_dir",
            moore_ct2,
            "--quantization",
            "int8",
            "--force",
        ],
        check=True,
    )
    log(f"moore convertie en {time.time() - t0:.0f}s")
    shutil.rmtree(merged_dir, ignore_errors=True)
    log("copie fp32 intermediaire supprimee")
else:
    log("moore deja convertie")


def size_mb(path):
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total / 1048576


log(f"TAILLES  base={size_mb(base_ct2):.0f} Mo   moore={size_mb(moore_ct2):.0f} Mo")
log("TERMINE")
