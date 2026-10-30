"""
Teste le modèle Mooré fine-tuné intégré, via le vrai translation_service
(donc avec le routage pivot fr<->en<->mos inclus), et compare directement aux
phrases problématiques identifiées sur le baseline (dégénérescence par
répétition, dérive de sens en rétro-traduction — voir docs/apprentissage).
"""

import sys

sys.path.insert(0, ".")
sys.stdout.reconfigure(encoding="utf-8")

from app.translation_service import translation_service  # noqa: E402

translation_service.load()

print("=== Cas direct : anglais <-> mooré (le modèle fine-tuné a vu ce type de données) ===")
print("en->mos:", translation_service.translate("How are you? My name is Amadou.", "en", "mos"))
print("mos->en:", translation_service.translate("Sũ-noog daarã, fo maanda wãn-wãna?", "mos", "en"))

print("\n=== Cas pivot : français <-> mooré (le vrai cas d'usage de l'app) ===")
fr_text = "Le marché est fermé aujourd'hui à cause de la pluie."
print("Rappel : ce texte dégénérait en boucle de répétition sur le baseline (voir Entrée 2 du journal).")
mos_translation = translation_service.translate(fr_text, "fr", "mos")
print(f"fr->mos: {fr_text}\n       -> {mos_translation}")

print("\nTest de rétro-traduction (comme dans l'entrée 6 du journal) :")
fr_greeting = "Bonjour, comment vas-tu ?"
mos_greeting = translation_service.translate(fr_greeting, "fr", "mos")
back_to_fr = translation_service.translate(mos_greeting, "mos", "fr")
print(f"fr  : {fr_greeting}")
print(f"mos : {mos_greeting}")
print(f"fr (retour) : {back_to_fr}")

print("\n=== Sanity check : les autres langues ne sont pas affectées ===")
print("fr->en:", translation_service.translate("Bonjour, comment vas-tu ?", "fr", "en"))
