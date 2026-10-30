import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Petits secrets de l'appareil : clés de chiffrement des coffres locaux,
/// empreintes des codes PIN, jetons. Keystore Android / WebCrypto sur le web.
///
/// Interface minimale pour pouvoir la remplacer par [MemorySecretStore] dans
/// les tests (le vrai stockage sécurisé n'existe pas hors d'un appareil).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();
}
