# laafi_ma — application Flutter (Android + web)

Application « Laafi Ma » : santé et protection des femmes au Burkina Faso, à la
voix (français, mooré, dioula). Contrat d'API : [docs/API.md](../docs/API.md).

## Architecture

```
lib/
  core/       l10n (tous les textes), réseau (jeton par requête), coffres chiffrés
              (Hive + AES, clés dans flutter_secure_storage), sécurité (PIN, leurre,
              calculatrice, session), routage, thème
  shared/     écoute à voix haute, lecteur audio, micro, sélecteurs, widgets communs
  features/
    onboarding/  lock/  home/  settings/  stats/
    assistant/   (module 1)   carnet/ (module 2)   help/ (module 3)
    agent/       (module 4)   learn/  (module 5)
    translate_text/ translate_voice/ translate_voice_message/  (espace agent)
```

## Lancer

```
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter run -d <android> --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`web/flutter_bootstrap.js` force le moteur CanvasKit (sinon page blanche sur
certaines machines). Vérifications : `dart format --line-length 120 lib test`,
`flutter analyze`, `flutter test`, `flutter build web --release`.

## Protection (rappel des choix)

- **Téléphone partagé** : jusqu'à 3 profils réels (`PinSlot.real`, `real2`,
  `real3`), chacun avec son code, son code de la page Aide, sa phrase d'aide et
  son coffre (`laafi_real`, `laafi_real_2`, `laafi_real_3`). Le profil 1 garde
  le coffre historique : aucune migration. Les réglages du téléphone (leurre,
  calculatrice, icône, sauvegarde, tout effacer) restent dans le profil 1.
- **Phrase d'aide secrète** : comparée sur le téléphone (`matchesSecretPhrase`)
  AVANT tout envoi d'une question écrite et après la reconnaissance d'une
  question vocale ; si c'est elle, rien ne part et la page Aide s'ouvre.
- **Icône « Calculatrice »** (Android) : alias `.CalculatorAlias` du manifeste,
  basculé par le canal `bf.ztech.laafima/disguise` (`MainActivity.kt`).
