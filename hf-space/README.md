---
title: Laafi Ma Voice
colorFrom: green
colorTo: yellow
sdk: gradio
sdk_version: 6.31.0
python_version: "3.12"
app_file: app.py
pinned: false
license: cc-by-nc-4.0
short_description: Voix et traduction fr, mooré, dioula pour Laafi Ma
models:
  - openai/whisper-small
  - facebook/mms-1b-all
  - facebook/nllb-200-distilled-600M
  - facebook/mms-tts-fra
  - facebook/mms-tts-mos
  - facebook/mms-tts-dyu
---

# Laafi Ma — voix et traduction

Ce Space fait tourner les modèles d'IA de [Laafi Ma](https://github.com/zongorene02/laafi-ma),
une application de santé à la voix pour les femmes du Burkina Faso, en
français, mooré et dioula. L'API de Laafi Ma l'appelle à distance ; il n'est
pas fait pour le public.

| Point d'entrée | Entrée | Sortie |
|---|---|---|
| `/transcribe` | fichier audio, langue (`fr`, `mos`, `dyu`) | texte |
| `/translate` | texte (5000 caractères max), langue source, langue cible | texte |
| `/synthesize` | texte (20000 caractères max), langue | audio `.wav` |
| `/health` | rien | état du Space (sans carte graphique) |

Modèles : Whisper-small (français), MMS-1b-all (mooré, dioula), NLLB-200
distilled 600M avec un adaptateur LoRA mooré (`moore-nllb-lora-adapter/`,
traduction par l'anglais pour le mooré), MMS-TTS (synthèse vocale).

**Licence : usage non commercial uniquement.** NLLB-200, MMS et l'adaptateur
mooré sont sous licence CC-BY-NC 4.0. Whisper est sous licence MIT.

Confidentialité : aucun texte ni aucun audio n'est journalisé. Les fichiers
reçus sont effacés dès leur lecture ; les audios produits restent au plus une
vingtaine de minutes dans le cache de Gradio, le temps d'être téléchargés.

Matériel : ZeroGPU. Le code de ce Space vient du dossier `hf-space/` du dépôt
Laafi Ma ; la logique sans modèle (`voice_logic.py`) y est testée.
