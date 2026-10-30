# Fiche d'arbitrage — à faire relire par un locuteur natif

**Pourquoi cette fiche.** Le système peut tourner beaucoup plus vite (une traduction
Mooré passe de 52 secondes à 2 ou 3 secondes), mais les réglages qui donnent cette
vitesse produisent des **mots différents**. Personne dans l'équipe technique ne lit le
Mooré, le Dioula ou le Bambara : seule une relecture humaine permet de décider si l'on
peut adopter la version rapide.

**Ce qu'on vous demande.** Pour chaque phrase, indiquer quelle version est correcte —
ou si les deux le sont, ou si aucune ne l'est. Aucune connaissance technique requise.

Mesures faites le 8 septembre 2026 sur la machine de développement.

---

## 1. Français → Mooré

**Phrase française :** « Le marché est fermé aujourd'hui à cause de la pluie. »

| Version | Traduction produite | Temps |
|---|---|---|
| **A — actuelle** | Zĩ-gũudã yika rũndã-rũndã, sa-kẽemã yĩnga. | 52 s |
| **B — recherche réduite** | Bãagẽ wã yaa kaoose, saagã yĩnga. | 20 s |
| **C — moteur rapide** | Zĩ-gũudã yika rũnna, saaga yĩnga. | 4,9 s |

Votre verdict : ................................................................

---

**Phrase française :** « Bonjour, comment vas-tu ? »

| Version | Traduction produite | Temps |
|---|---|---|
| **A — actuelle** | Sãmbg ka be, fo yaa wãn-wãna? | 52 s |
| **B — recherche réduite** | Sãmbg ka be, fo yaa wãn-wãna? *(identique à A)* | 14 s |
| **C — moteur rapide** | Salou, fo yaa wãn-wãna? | 2,4 s |

> Point d'attention : « Salou » ressemble à une transcription du français « salut ».
> Si ce n'est pas du Mooré correct, la version C est disqualifiée pour cette phrase.

Votre verdict : ................................................................

---

## 2. Français → Dioula

**Phrase française :** « Où se trouve le centre de santé le plus proche ? »

| Version | Traduction produite | Temps |
|---|---|---|
| **A — actuelle** | K'a sɔrɔ dɔgɔtɔrɔso min ka surun i ma, o be min? | 18,6 s |
| **B — recherche réduite** | *identique à A* | 12,8 s |
| **C — moteur rapide** | K'a sɔrɔ dɔgɔtɔrɔso min ka surun i ma, o be yɔrɔ jumɛn? | 2,7 s |

Votre verdict : ................................................................

---

## 3. Français → Bambara

**Phrase française :** « Prenez ce médicament deux fois par jour. »

| Version | Traduction produite | Temps |
|---|---|---|
| **A — actuelle** | Aw bɛ nin fura ta siɲɛ fila tile kɔnɔ. | 11,2 s |
| **B — recherche réduite** | *identique à A* | 8,3 s |
| **C — moteur rapide** | Aw bɛ nin furakisɛ ta siɲɛ fila tile kɔnɔ. | 1,7 s |

Votre verdict : ................................................................

---

## Ce que chaque réponse déclenche

- **Si la version A reste la meilleure** : on garde le système tel quel. Il est lent,
  mais sa qualité est vérifiée. La lenteur se corrigera par du matériel, pas par un
  réglage.
- **Si la version C est jugée équivalente ou meilleure** : on bascule sur le moteur
  rapide. Les traductions deviennent 7 à 20 fois plus rapides, la mémoire nécessaire
  est divisée par deux, et le service devient déployable sur un hébergement gratuit.
  Il faudra alors refaire cette relecture sur un échantillon plus large avant de
  parler de « validé par un locuteur natif » dans un dossier de candidature.
- **Si les versions divergent selon les phrases** : c'est le signal qu'il faut
  constituer le jeu de test de référence prévu au budget, et mesurer proprement plutôt
  que de décider sur cinq phrases.

## Note technique

- Version A : moteur `transformers`, pleine précision, recherche en faisceau à 5.
- Version B : identique à A, recherche en faisceau à 2.
- Version C : moteur CTranslate2, poids quantifiés en int8, recherche en faisceau à 5.
  Modèles convertis présents dans `backend/services/core-service/models/nllb-*-int8`
  (1,2 Go au total, non versionnés). Scripts de conversion et de mesure dans le dossier
  de candidature (`generer_*`), réutilisables tels quels.
- Aucun de ces réglages n'est actif aujourd'hui : le service tourne en version A.
