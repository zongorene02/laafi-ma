import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

import 'json_store.dart';

/// [JsonStore] sur deux boîtes Hive chiffrées en AES-256 (`HiveAesCipher`) :
/// une boîte de documents JSON (en mémoire, petite) et une boîte PARESSEUSE
/// pour les blobs (photos, audio), lus seulement à la demande pour ne pas
/// charger tous les fichiers en mémoire au démarrage.
///
/// Fonctionne à l'identique sur Android (fichiers) et sur le web (IndexedDB).
class HiveJsonStore implements JsonStore {
  HiveJsonStore._(this._docs, this._blobs);

  final Box<String> _docs;
  final LazyBox<Uint8List> _blobs;

  static Future<HiveJsonStore> open(String name, List<int> key) async {
    final cipher = HiveAesCipher(key);
    final docs = await Hive.openBox<String>(name, encryptionCipher: cipher);
    final blobs = await Hive.openLazyBox<Uint8List>('${name}_blobs', encryptionCipher: cipher);
    return HiveJsonStore._(docs, blobs);
  }

  /// Efface les deux boîtes d'un coffre, ouvertes ou non.
  static Future<void> deleteFromDisk(String name) async {
    await Hive.deleteBoxFromDisk(name);
    await Hive.deleteBoxFromDisk('${name}_blobs');
  }

  Map<String, dynamic> _decode(String raw) => (jsonDecode(raw) as Map).cast<String, dynamic>();

  @override
  Future<List<Map<String, dynamic>>> list(String collection) async {
    final prefix = '$collection/';
    final result = <Map<String, dynamic>>[];
    for (final key in _docs.keys) {
      if (key is String && key.startsWith(prefix)) {
        final raw = _docs.get(key);
        if (raw != null) result.add(_decode(raw));
      }
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) async {
    final raw = _docs.get(storeKey(collection, id));
    return raw == null ? null : _decode(raw);
  }

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> value) =>
      _docs.put(storeKey(collection, id), jsonEncode(value));

  @override
  Future<void> delete(String collection, String id) => _docs.delete(storeKey(collection, id));

  @override
  Future<void> clearCollection(String collection) async {
    final keys = _docs.keys.where((key) => key is String && key.startsWith('$collection/')).toList();
    await _docs.deleteAll(keys);
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> dump() async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final key in _docs.keys) {
      if (key is! String) continue;
      final raw = _docs.get(key);
      if (raw == null) continue;
      result.putIfAbsent(key.split('/').first, () => []).add(_decode(raw));
    }
    return result;
  }

  @override
  Future<Uint8List?> getBlob(String id) => _blobs.get(id);

  @override
  Future<void> putBlob(String id, Uint8List bytes) => _blobs.put(id, bytes);

  @override
  Future<void> deleteBlob(String id) => _blobs.delete(id);

  @override
  Future<List<String>> blobIds() async => _blobs.keys.whereType<String>().toList();

  @override
  Future<void> clearAll() async {
    await _docs.clear();
    await _blobs.clear();
  }
}
