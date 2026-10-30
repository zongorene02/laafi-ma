import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../storage/secret_store.dart';
import '../utils/text.dart';

/// Part minimale de mots communs pour reconnaître la phrase d'aide.
const secretPhraseMinOverlap = 0.8;

/// Une phrase trop courte se déclencherait par hasard : au moins 3 mots.
const secretPhraseMinWords = 3;

bool isValidSecretPhrase(String phrase) {
  final normalized = normalizeText(phrase);
  return normalized.isNotEmpty && normalized.split(' ').length >= secretPhraseMinWords;
}

/// Logique PURE : [text] (question tapée ou reconnue à la voix) est-elle la
/// phrase d'aide secrète ([phrase]) ?
///
/// Les deux textes sont normalisés (minuscules, sans accents ni ponctuation,
/// espaces réduits). Accepté s'ils sont égaux, ou si les mots en commun
/// représentent au moins 80 % des mots du plus long des deux : la
/// reconnaissance vocale peut se tromper sur un petit mot, mais une vraie
/// question de santé ne déclenche pas l'aide par hasard.
bool matchesSecretPhrase(String text, String? phrase) {
  if (phrase == null) return false;
  final expected = normalizeText(phrase);
  final actual = normalizeText(text);
  if (expected.isEmpty || actual.isEmpty) return false;
  if (expected == actual) return true;
  final a = expected.split(' ').toSet();
  final b = actual.split(' ').toSet();
  final common = a.intersection(b).length;
  final longest = a.length > b.length ? a.length : b.length;
  return common / longest >= secretPhraseMinOverlap;
}

/// Phrase d'aide secrète (« code vocal », module 3), une par profil réel.
/// Rangée dans le stockage sécurisé du système, jamais envoyée au serveur.
class SecretPhraseStore {
  SecretPhraseStore(this._secrets);

  final SecretStore _secrets;

  static String keyFor(int profile) => 'help_phrase_$profile';

  Future<String?> read(int profile) => _secrets.read(keyFor(profile));

  Future<void> write(int profile, String phrase) => _secrets.write(keyFor(profile), phrase.trim());

  Future<void> clear(int profile) => _secrets.delete(keyFor(profile));
}

final secretPhraseStoreProvider = Provider<SecretPhraseStore>(
  (ref) => SecretPhraseStore(ref.watch(secretStoreProvider)),
);
