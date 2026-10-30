"""
Premier test de la brique voix : synthèse vocale (TTS) + reconnaissance
vocale (STT), avec un test d'aller-retour pour valider sans microphone ni
locuteur natif sous la main (même logique que la rétro-traduction utilisée
pour le texte).

Modèles :
- TTS : facebook/mms-tts-<code> (projet MMS de Meta, "Massively Multilingual
  Speech"). Architecture VITS : contrairement à NLLB/Whisper qui sont des
  Transformers encodeur-décodeur, VITS est un modèle "flow-based" combiné à
  un GAN (réseau antagoniste génératif) : il apprend à transformer du bruit
  aléatoire en forme d'onde audio réaliste, conditionné par le texte. Un
  modèle séparé par langue (contrairement à NLLB qui est un seul modèle pour
  200 langues).
- STT : openai/whisper-small, via le pipeline "automatic-speech-recognition"
  de transformers. Whisper découpe l'audio en fenêtres de 30s, les convertit
  en spectrogramme (représentation temps/fréquence du son), puis un
  Transformer encodeur-décodeur (comme NLLB, mais pour l'audio) génère le
  texte correspondant.

Découverte importante : MMS de Meta a bien un modèle TTS pour le Mooré
(facebook/mms-tts-mos), alors que notre recherche précédente n'avait trouvé
AUCUNE ressource audio publique pour cette langue. Explication probable :
MMS a été entraîné sur des enregistrements de lectures bibliques dans des
centaines de langues (un corpus fermé, pas forcément indexé comme "dataset
public" par les moteurs de recherche/HuggingFace), un peu comme JW300 pour le
texte. Cela ne veut pas dire que la qualité est bonne : à vérifier à l'oreille
par un locuteur natif, comme toujours pour ces langues.
"""

import sys
import time

import soundfile as sf
import torch
from transformers import AutoTokenizer, VitsModel, pipeline

sys.stdout.reconfigure(encoding="utf-8")

TTS_LANGS = {
    "fra": ("Français", "Bonjour, comment vas-tu ? Je m'appelle Amadou et j'habite à Ouagadougou."),
    "mos": ("Mooré", "Sũ-noog daarã, fo maanda wãn-wãna?"),
    "bam": ("Bambara", "I bɛ cogo di? Ne tɔgɔ ye ko Amadou."),
    "dyu": ("Dioula", "I be cogo di? N' tɔgɔ ko Amadou."),
}


def synthesize_all():
    """Génère un fichier .wav par langue avec MMS-TTS."""
    for code, (name, text) in TTS_LANGS.items():
        print(f"\n--- Synthèse {name} ({code}) ---")
        model_name = f"facebook/mms-tts-{code}"
        t0 = time.time()
        model = VitsModel.from_pretrained(model_name)
        tokenizer = AutoTokenizer.from_pretrained(model_name)

        inputs = tokenizer(text, return_tensors="pt")
        with torch.no_grad():
            output = model(**inputs).waveform

        wav_path = f"audio_test_{code}.wav"
        sf.write(wav_path, output.squeeze().numpy(), model.config.sampling_rate)
        print(f"Texte   : {text}")
        print(f"Fichier : {wav_path} ({time.time() - t0:.1f}s, {model.config.sampling_rate} Hz)")


def roundtrip_check_french():
    """TTS français -> STT (Whisper) -> compare au texte de départ."""
    print(f"\n{'=' * 60}")
    print("  TEST ALLER-RETOUR : Français -> voix -> Français")
    print(f"{'=' * 60}")

    original_text = TTS_LANGS["fra"][1]
    print("Chargement de Whisper (openai/whisper-small)...")
    asr = pipeline("automatic-speech-recognition", model="openai/whisper-small")

    # Le pipeline sait lire un fichier audio tout seul, mais passe par le
    # programme externe "ffmpeg" pour ça — absent sur cette machine. On
    # contourne en chargeant nous-mêmes l'audio (avec soundfile, déjà
    # installé) et en donnant directement le tableau de nombres + la
    # fréquence d'échantillonnage : c'est aussi ce qu'on fera plus tard dans
    # l'API pour traiter l'audio envoyé par l'app mobile, sans dépendance
    # externe à installer sur le serveur.
    audio_array, sampling_rate = sf.read("audio_test_fra.wav")
    result = asr(
        {"raw": audio_array, "sampling_rate": sampling_rate},
        generate_kwargs={"language": "french"},
    )

    print(f"\nTexte original     : {original_text}")
    print(f"Texte après TTS+STT : {result['text']}")


if __name__ == "__main__":
    # Les 4 fichiers audio ont déjà été générés lors du run précédent
    # (audio_test_fra.wav, audio_test_mos.wav, audio_test_bam.wav,
    # audio_test_dyu.wav) — pas besoin de refaire la synthèse.
    roundtrip_check_french()
