import 'dart:convert';
import 'dart:typed_data';

/// Stockage local de documents JSON rangés par collection, plus des blobs
/// binaires (photos, notes vocales, audio en cache).
///
/// Tout passe par cette interface : l'implémentation réelle ([HiveJsonStore],
/// chiffrée en AES) et celle des tests ([MemoryJsonStore]) sont
/// interchangeables, ce qui permet de tester toute la logique métier sans
/// disque ni plugin.
abstract class JsonStore {
  Future<List<Map<String, dynamic>>> list(String collection);
  Future<Map<String, dynamic>?> get(String collection, String id);
  Future<void> put(String collection, String id, Map<String, dynamic> value);
  Future<void> delete(String collection, String id);
  Future<void> clearCollection(String collection);

  /// Toutes les collections non vides, pour l'export de sauvegarde.
  Future<Map<String, List<Map<String, dynamic>>>> dump();

  Future<Uint8List?> getBlob(String id);
  Future<void> putBlob(String id, Uint8List bytes);
  Future<void> deleteBlob(String id);
  Future<List<String>> blobIds();

  Future<void> clearAll();
}

String storeKey(String collection, String id) => '$collection/$id';

/// Copie profonde par aller-retour JSON : un appelant qui modifie la map
/// reçue ne doit jamais modifier en douce ce qui est stocké.
Map<String, dynamic> cloneJson(Map<String, dynamic> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();

class MemoryJsonStore implements JsonStore {
  final Map<String, String> _docs = {};
  final Map<String, Uint8List> _blobs = {};

  @override
  Future<List<Map<String, dynamic>>> list(String collection) async {
    final prefix = '$collection/';
    return [
      for (final entry in _docs.entries)
        if (entry.key.startsWith(prefix)) (jsonDecode(entry.value) as Map).cast<String, dynamic>(),
    ];
  }

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) async {
    final raw = _docs[storeKey(collection, id)];
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> value) async {
    _docs[storeKey(collection, id)] = jsonEncode(value);
  }

  @override
  Future<void> delete(String collection, String id) async {
    _docs.remove(storeKey(collection, id));
  }

  @override
  Future<void> clearCollection(String collection) async {
    _docs.removeWhere((key, _) => key.startsWith('$collection/'));
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> dump() async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in _docs.entries) {
      final collection = entry.key.split('/').first;
      result.putIfAbsent(collection, () => []).add((jsonDecode(entry.value) as Map).cast<String, dynamic>());
    }
    return result;
  }

  @override
  Future<Uint8List?> getBlob(String id) async => _blobs[id];

  @override
  Future<void> putBlob(String id, Uint8List bytes) async => _blobs[id] = bytes;

  @override
  Future<void> deleteBlob(String id) async => _blobs.remove(id);

  @override
  Future<List<String>> blobIds() async => _blobs.keys.toList();

  @override
  Future<void> clearAll() async {
    _docs.clear();
    _blobs.clear();
  }
}
