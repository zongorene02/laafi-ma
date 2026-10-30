import 'dart:convert';
import 'dart:math';

import 'hive_json_store.dart';
import 'json_store.dart';
import 'secret_store.dart';

/// Noms des coffres locaux. Chacun a sa propre clé AES-256, tirée au hasard à
/// la première ouverture et conservée dans le stockage sécurisé du système.
abstract final class VaultName {
  /// Réglages globaux nécessaires AVANT déverrouillage (langue, déguisement…).
  static const meta = 'laafi_meta';

  /// Contenus publics mis en cache (FAQ, capsules, annuaire) et file des
  /// statistiques anonymes. Partagé par les deux profils.
  static const cache = 'laafi_cache';

  /// Carnet, journal, contacts de confiance : profil réel (profil 1).
  static const real = 'laafi_real';

  /// Profils 2 et 3 d'un téléphone partagé, chacun avec sa propre clé.
  static const real2 = 'laafi_real_2';
  static const real3 = 'laafi_real_3';

  /// Profil leurre (code PIN de diversion) : volontairement vide au départ.
  static const decoy = 'laafi_decoy';

  /// Données de l'espace agent (bénéficiaires, visites, file de synchro).
  static const agent = 'laafi_agent';

  static const all = [meta, cache, real, real2, real3, decoy, agent];

  /// Coffre d'un profil réel : le profil 1 garde le coffre historique
  /// `laafi_real` (aucune migration pour les utilisatrices existantes).
  static String profile(int profile) => switch (profile) {
    2 => real2,
    3 => real3,
    _ => real,
  };
}

typedef StoreOpener = Future<JsonStore> Function(String name, List<int> key);
typedef StoreDeleter = Future<void> Function(String name);

class VaultService {
  VaultService(this._secrets, {StoreOpener? opener, StoreDeleter? deleter})
    : _opener = opener ?? HiveJsonStore.open,
      _deleter = deleter ?? HiveJsonStore.deleteFromDisk;

  final SecretStore _secrets;
  final StoreOpener _opener;
  final StoreDeleter _deleter;
  final Map<String, JsonStore> _open = {};

  static String keySecretName(String name) => 'vault_key_$name';

  Future<List<int>> _keyFor(String name) async {
    final secretName = keySecretName(name);
    final existing = await _secrets.read(secretName);
    if (existing != null) return base64Decode(existing);
    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    await _secrets.write(secretName, base64Encode(key));
    return key;
  }

  Future<JsonStore> open(String name) async {
    final cached = _open[name];
    if (cached != null) return cached;
    final store = await _opener(name, await _keyFor(name));
    _open[name] = store;
    return store;
  }

  /// Efface UN coffre (profil retiré d'un téléphone partagé) : contenu,
  /// fichier sur le disque, puis sa clé.
  Future<void> wipe(String name) async {
    final store = _open.remove(name) ?? await _opener(name, await _keyFor(name));
    await store.clearAll();
    try {
      await _deleter(name);
    } catch (_) {
      // Boîte jamais écrite sur le disque : rien de plus à effacer.
    }
    await _secrets.delete(keySecretName(name));
  }

  /// « Supprimer toutes mes données » : boîtes effacées du disque, puis TOUS
  /// les secrets (clés, empreintes de PIN, jetons). Sans les clés, même une
  /// copie des fichiers récupérée avant l'effacement resterait illisible.
  Future<void> wipeAll() async {
    for (final store in _open.values) {
      await store.clearAll();
    }
    _open.clear();
    for (final name in VaultName.all) {
      try {
        await _deleter(name);
      } catch (_) {
        // Une boîte jamais créée ne doit pas empêcher d'effacer les autres.
      }
    }
    await _secrets.deleteAll();
  }
}
