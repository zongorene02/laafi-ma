import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/security/session.dart';
import '../../../core/storage/json_store.dart';
import '../../../core/utils/dates.dart';
import '../domain/health_calc.dart';

/// Noms des collections du coffre d'un profil (réel ou leurre).
abstract final class Col {
  static const healthProfile = 'health_profile';
  static const cycles = 'cycles';
  static const contraception = 'contraception';
  static const pregnancy = 'pregnancy';
  static const prenatalVisits = 'prenatal_visits';
  static const exams = 'exams';
  static const weights = 'weights';
  static const bloodPressure = 'blood_pressure';
  static const postpartum = 'postpartum';
  static const postpartumLogs = 'postpartum_logs';
  static const children = 'children';
  static const vaccines = 'vaccines';
  static const consultations = 'consultations';
  static const documents = 'documents';
  static const medicines = 'medicines';
  static const agenda = 'agenda';
  static const moods = 'moods';
  static const journal = 'journal';
  static const contacts = 'contacts';
  static const account = 'account';

  /// Journal des partages : un élément par QR code créé.
  static const shareLog = 'share_log';
}

/// Liste d'une collection du profil ouvert, triée par date décroissante.
/// Une seule implémentation pour toutes les rubriques du carnet.
class CollectionNotifier extends FamilyAsyncNotifier<List<Map<String, dynamic>>, String> {
  JsonStore get _store => ref.read(profileStoreProvider);

  @override
  Future<List<Map<String, dynamic>>> build(String arg) async {
    final store = ref.watch(profileStoreProvider);
    return sortRecords(await store.list(arg));
  }

  /// Crée ou met à jour ; renvoie l'identifiant.
  Future<String> save(Map<String, dynamic> record) async {
    final id = (record['id'] as String?) ?? const Uuid().v4();
    final value = {...record, 'id': id, 'updated_at': utcTimestamp(DateTime.now())};
    await _store.put(arg, id, value);
    final list = [...(state.valueOrNull ?? const <Map<String, dynamic>>[])]..removeWhere((r) => r['id'] == id);
    state = AsyncData(sortRecords([...list, value]));
    return id;
  }

  Future<void> remove(String id) async {
    await _store.delete(arg, id);
    state = AsyncData([...(state.valueOrNull ?? const <Map<String, dynamic>>[])]..removeWhere((r) => r['id'] == id));
  }
}

/// Plus récent d'abord : par `date` si présente, sinon par `updated_at`.
List<Map<String, dynamic>> sortRecords(List<Map<String, dynamic>> records) {
  String key(Map<String, dynamic> r) => '${r['date'] ?? r['start_date'] ?? ''}|${r['updated_at'] ?? ''}';
  return records..sort((a, b) => key(b).compareTo(key(a)));
}

final collectionProvider = AsyncNotifierProvider.family<CollectionNotifier, List<Map<String, dynamic>>, String>(
  CollectionNotifier.new,
);

/// Document unique d'une collection (profil santé, grossesse en cours…).
final singleRecordProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, collection) async {
  final list = await ref.watch(collectionProvider(collection).future);
  return list.isEmpty ? null : list.first;
});

/// Le profil ouvert est-il celui d'une mineure (moins de 18 ans) ?
final isMinorProvider = FutureProvider<bool>((ref) async {
  return isMinorProfile(await ref.watch(singleRecordProvider(Col.healthProfile).future));
});
