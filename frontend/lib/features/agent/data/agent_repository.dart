import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/json_store.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/storage/vault.dart';
import '../../../core/utils/dates.dart';
import 'sync_merge.dart';

/// Profil renvoyé par `GET /auth/me`.
class StaffUser {
  const StaffUser({required this.id, required this.role, this.email, this.fullName, this.districtId});

  factory StaffUser.fromJson(Map<String, dynamic> json) => StaffUser(
    id: json['id'] as String,
    role: json['role'] as String,
    email: json['email'] as String?,
    fullName: json['full_name'] as String?,
    districtId: json['district_id'] as String?,
  );

  final String id;
  final String role;
  final String? email;
  final String? fullName;
  final String? districtId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'email': email,
    'full_name': fullName,
    'district_id': districtId,
  };
}

class AgentSummary {
  const AgentSummary({
    required this.beneficiaries,
    required this.pregnant,
    required this.visitsLast30Days,
    required this.referralsLast30Days,
    required this.dangerSignsLast30Days,
  });

  factory AgentSummary.fromJson(Map<String, dynamic> json) => AgentSummary(
    beneficiaries: (json['beneficiaries'] as num).toInt(),
    pregnant: (json['pregnant'] as num).toInt(),
    visitsLast30Days: (json['visits_last_30_days'] as num).toInt(),
    referralsLast30Days: (json['referrals_last_30_days'] as num).toInt(),
    dangerSignsLast30Days: (json['danger_signs_last_30_days'] as num).toInt(),
  );

  final int beneficiaries;
  final int pregnant;
  final int visitsLast30Days;
  final int referralsLast30Days;
  final int dangerSignsLast30Days;
}

class SyncResponse {
  const SyncResponse({required this.serverTime, required this.collections});

  factory SyncResponse.fromJson(Map<String, dynamic> json) => SyncResponse(
    serverTime: json['server_time'] as String,
    collections: {
      for (final name in AgentCollections.all)
        name: [for (final r in (json[name] as List? ?? const [])) (r as Map).cast<String, dynamic>()],
    },
  );

  final String serverTime;
  final Map<String, List<Map<String, dynamic>>> collections;
}

abstract final class AgentCollections {
  static const beneficiaries = 'beneficiaries';
  static const visits = 'visits';
  static const gbvReferrals = 'gbv_referrals';
  static const all = [beneficiaries, visits, gbvReferrals];
}

/// Endpoints de l'espace agent (jeton `staff`).
class AgentApi {
  AgentApi(this._dio);

  final Dio _dio;

  Future<String> login(String email, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {'email': email, 'password': password});
      return response.data['access_token'] as String;
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<StaffUser> me() async {
    try {
      final response = await _dio.get('/auth/me', options: scoped(AuthScope.staff));
      return StaffUser.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<SyncResponse> sync(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/agent/sync', data: body, options: scoped(AuthScope.staff));
      return SyncResponse.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<AgentSummary> summary() async {
    try {
      final response = await _dio.get('/agent/summary', options: scoped(AuthScope.staff));
      return AgentSummary.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }
}

/// Données de l'agent, d'abord enregistrées sur le téléphone (identifiants
/// UUID v4 créés localement), puis envoyées par `POST /agent/sync`.
class AgentRepository {
  AgentRepository(this._api, this._store);

  final AgentApi _api;
  final JsonStore _store;

  static const metaCollection = 'agent_meta';

  /// Numéros de téléphone des bénéficiaires : collection LOCALE seulement,
  /// hors de [AgentCollections.all], donc jamais envoyée par [sync].
  static const phonesCollection = 'beneficiary_phones';

  Future<List<Map<String, dynamic>>> list(String collection) async {
    final records = await _store.list(collection);
    return records.where((r) => r['deleted'] != true).toList();
  }

  /// Enregistre localement et marque « à envoyer ».
  Future<void> save(String collection, Map<String, dynamic> record) async {
    final value = {...record, 'updated_at': utcTimestamp(DateTime.now()), dirtyFlag: true};
    await _store.put(collection, value['id'] as String, value);
  }

  /// Suppression douce (`deleted: true`), propagée au serveur. Le numéro
  /// local d'une bénéficiaire supprimée est effacé.
  Future<void> softDelete(String collection, Map<String, dynamic> record) async {
    await save(collection, {...record, 'deleted': true});
    if (collection == AgentCollections.beneficiaries) await setPhone(record['id'] as String, null);
  }

  Future<String?> phoneOf(String beneficiaryId) async =>
      (await _store.get(phonesCollection, beneficiaryId))?['phone'] as String?;

  /// Note (ou efface, si vide) le numéro d'une bénéficiaire, sur ce
  /// téléphone uniquement.
  Future<void> setPhone(String beneficiaryId, String? phone) async {
    final value = phone?.trim() ?? '';
    if (value.isEmpty) {
      await _store.delete(phonesCollection, beneficiaryId);
    } else {
      await _store.put(phonesCollection, beneficiaryId, {'id': beneficiaryId, 'phone': value});
    }
  }

  Future<Map<String, String>> phones() async => {
    for (final r in await _store.list(phonesCollection)) r['id'] as String: r['phone'].toString(),
  };

  Future<int> pendingCount() async {
    var count = 0;
    for (final name in AgentCollections.all) {
      count += pendingRecords(await _store.list(name)).length;
    }
    return count;
  }

  Future<String?> lastSync() async => (await _store.get(metaCollection, 'sync'))?['since'] as String?;

  Future<void> sync() async {
    final since = await lastSync();
    final local = {for (final name in AgentCollections.all) name: await _store.list(name)};
    final sent = {for (final name in AgentCollections.all) name: pendingRecords(local[name]!)};
    final response = await _api.sync({
      'since': since,
      AgentCollections.beneficiaries: sent[AgentCollections.beneficiaries],
      AgentCollections.visits: sent[AgentCollections.visits],
      AgentCollections.gbvReferrals: sent[AgentCollections.gbvReferrals],
    });
    for (final name in AgentCollections.all) {
      final merged = mergeAfterSync(local: local[name]!, sent: sent[name]!, server: response.collections[name]!);
      for (final record in merged) {
        await _store.put(name, record['id'] as String, record);
      }
    }
    await _store.put(metaCollection, 'sync', {'since': response.serverTime});
  }

  Future<AgentSummary> summary() => _api.summary();

  /// Résumé calculé sur le téléphone quand le serveur est injoignable.
  Future<AgentSummary> localSummary() async {
    final beneficiaries = await list(AgentCollections.beneficiaries);
    final visits = await list(AgentCollections.visits);
    final referrals = await list(AgentCollections.gbvReferrals);
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    bool recent(Object? date) => (parseDate(date) ?? DateTime(2000)).isAfter(cutoff);
    final recentVisits = visits.where((v) => recent(v['visit_date'])).toList();
    return AgentSummary(
      beneficiaries: beneficiaries.length,
      pregnant: beneficiaries.where((b) => b['pregnant'] == true).length,
      visitsLast30Days: recentVisits.length,
      referralsLast30Days:
          recentVisits.where((v) => v['referred'] == true).length +
          referrals.where((r) => recent(r['referral_date'])).length,
      dangerSignsLast30Days: recentVisits.where((v) => (v['danger_sign_ids'] as List? ?? const []).isNotEmpty).length,
    );
  }

  Future<StaffUser?> cachedUser() async {
    final doc = await _store.get(metaCollection, 'user');
    return doc == null ? null : StaffUser.fromJson(doc);
  }

  Future<void> saveUser(StaffUser user) => _store.put(metaCollection, 'user', user.toJson());

  Future<void> clearAll() => _store.clearAll();
}

final agentApiProvider = Provider<AgentApi>((ref) => AgentApi(ref.watch(dioProvider)));

final agentStoreProvider = FutureProvider<JsonStore>((ref) => ref.watch(vaultProvider).open(VaultName.agent));

final agentRepositoryProvider = FutureProvider<AgentRepository>((ref) async {
  return AgentRepository(ref.watch(agentApiProvider), await ref.watch(agentStoreProvider.future));
});

/// Session de l'agent connecté (`null` = non connecté). Fonctionne hors
/// connexion : le profil est relu depuis le coffre local tant que le jeton
/// est présent.
class AgentSessionController extends AsyncNotifier<StaffUser?> {
  @override
  Future<StaffUser?> build() async {
    ref.watch(staffAuthVersionProvider);
    final token = await ref.read(tokenStorageProvider).readToken(TokenKind.staff);
    if (token == null) return null;
    final repo = await ref.read(agentRepositoryProvider.future);
    return repo.cachedUser();
  }

  Future<void> login(String email, String password) async {
    final api = ref.read(agentApiProvider);
    final tokens = ref.read(tokenStorageProvider);
    final token = await api.login(email, password);
    await tokens.saveToken(TokenKind.staff, token);
    final user = await api.me();
    if (user.role != 'agent') {
      await tokens.clearToken(TokenKind.staff);
      throw ApiException('Ce compte n\'est pas un compte agent.', statusCode: 403);
    }
    final repo = await ref.read(agentRepositoryProvider.future);
    final previous = await repo.cachedUser();
    // Un autre agent sur le même téléphone ne doit jamais voir les données du
    // précédent.
    if (previous != null && previous.id != user.id) await repo.clearAll();
    await repo.saveUser(user);
    state = AsyncData(user);
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clearToken(TokenKind.staff);
    state = const AsyncData(null);
  }
}

final agentSessionProvider = AsyncNotifierProvider<AgentSessionController, StaffUser?>(AgentSessionController.new);
