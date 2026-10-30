import 'json_store.dart';

/// Une réponse d'API gardée pour la consultation hors connexion, avec sa date.
class CacheEntry {
  const CacheEntry(this.fetchedAt, this.data);

  final DateTime fetchedAt;
  final Object? data;
}

Future<void> writeCache(JsonStore store, String collection, String id, Object? data) =>
    store.put(collection, id, {'fetched_at': DateTime.now().toUtc().toIso8601String(), 'data': data});

Future<CacheEntry?> readCache(JsonStore store, String collection, String id) async {
  final doc = await store.get(collection, id);
  if (doc == null) return null;
  return CacheEntry(DateTime.tryParse(doc['fetched_at'] as String? ?? '') ?? DateTime(2000), doc['data']);
}
