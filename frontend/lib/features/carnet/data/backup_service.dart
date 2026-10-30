import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/security/session.dart';
import '../../../core/storage/json_store.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/utils/dates.dart';
import '../../stats/stats_service.dart';
import '../domain/backup_crypto.dart';
import 'records.dart';

/// Compte anonyme créé par `POST /auth/device`.
class DeviceAccount {
  const DeviceAccount({required this.accountId, required this.recoveryCode});

  final String accountId;
  final String recoveryCode;
}

/// Endpoints `/auth/device*`, `/auth/me` et `/records/backup` (rôle `woman`).
class DeviceAccountApi {
  DeviceAccountApi(this._dio);

  final Dio _dio;

  Future<(String token, DeviceAccount account)> createDevice() async {
    try {
      final response = await _dio.post('/auth/device');
      final data = (response.data as Map).cast<String, dynamic>();
      return (
        data['access_token'] as String,
        DeviceAccount(accountId: data['account_id'] as String, recoveryCode: data['recovery_code'] as String),
      );
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<String> recover(DeviceAccount account) async {
    try {
      final response = await _dio.post(
        '/auth/device/recover',
        data: {'account_id': account.accountId, 'recovery_code': account.recoveryCode},
      );
      return response.data['access_token'] as String;
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<void> deleteMe() async {
    try {
      await _dio.delete('/auth/me', options: scoped(AuthScope.device));
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<({String updatedAt, int sizeBytes})> putBackup(BackupPayload payload) async {
    try {
      final response = await _dio.put('/records/backup', data: payload.toJson(), options: scoped(AuthScope.device));
      final data = (response.data as Map).cast<String, dynamic>();
      return (updatedAt: data['updated_at'] as String, sizeBytes: (data['size_bytes'] as num).toInt());
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  /// `null` si aucune sauvegarde (404).
  Future<BackupPayload?> getBackup() async {
    try {
      final response = await _dio.get('/records/backup', options: scoped(AuthScope.device));
      return BackupPayload.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiClient.toApiException(e);
    }
  }

  Future<void> deleteBackup() async {
    try {
      await _dio.delete('/records/backup', options: scoped(AuthScope.device));
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }
}

/// Sauvegarde chiffrée du profil RÉEL.
///
/// Le numéro de compte et le code de récupération sont aussi gardés dans le
/// coffre chiffré du téléphone : ils servent à renouveler automatiquement le
/// jeton (valable 30 jours) via `/auth/device/recover`. Ils ne sont AFFICHÉS
/// qu'une seule fois, à la création.
class BackupService {
  BackupService({required this.api, required this.store, required this.tokens, this.maxBytes = 5 * 1024 * 1024});

  final DeviceAccountApi api;
  final JsonStore store;
  final TokenStorage tokens;
  final int maxBytes;

  static const accountDoc = 'device';
  static const metaDoc = 'backup_meta';

  Future<DeviceAccount?> account() async {
    final doc = await store.get(Col.account, accountDoc);
    if (doc == null) return null;
    return DeviceAccount(accountId: doc['account_id'] as String, recoveryCode: doc['recovery_code'] as String);
  }

  Future<void> _saveAccount(DeviceAccount account) => store.put(Col.account, accountDoc, {
    'id': accountDoc,
    'account_id': account.accountId,
    'recovery_code': account.recoveryCode,
    'created_at': utcTimestamp(DateTime.now()),
  });

  /// Crée le compte anonyme. Renvoie le compte pour l'affichage unique du code.
  Future<DeviceAccount> createAccount() async {
    final (token, account) = await api.createDevice();
    await tokens.saveToken(TokenKind.device, token);
    await _saveAccount(account);
    return account;
  }

  /// Rattache ce téléphone à un compte existant (nouveau téléphone).
  Future<void> attachAccount(DeviceAccount account) async {
    final token = await api.recover(account);
    await tokens.saveToken(TokenKind.device, token);
    await _saveAccount(account);
  }

  /// Exécute [action] ; si le jeton a expiré (401), le renouvelle une fois.
  Future<T> _withDeviceAuth<T>(Future<T> Function() action) async {
    if (await tokens.readToken(TokenKind.device) == null) {
      final existing = await account();
      if (existing == null) throw ApiException('Créez d\'abord un compte anonyme.');
      await tokens.saveToken(TokenKind.device, await api.recover(existing));
    }
    try {
      return await action();
    } on ApiException catch (e) {
      final existing = await account();
      if (!e.isUnauthorized || existing == null) rethrow;
      await tokens.saveToken(TokenKind.device, await api.recover(existing));
      return action();
    }
  }

  /// Contenu exporté : toutes les collections du profil (sauf le compte
  /// lui-même) et, si demandé, les photos et notes vocales.
  Future<List<int>> exportPlaintext({required bool includeMedia}) async {
    final dump = await store.dump()
      ..remove(Col.account)
      ..remove('meta');
    final blobs = <String, String>{};
    if (includeMedia) {
      for (final id in await store.blobIds()) {
        final bytes = await store.getBlob(id);
        if (bytes != null) blobs[id] = base64Encode(bytes);
      }
    }
    return utf8.encode(
      jsonEncode({
        'schema_version': 1,
        'exported_at': utcTimestamp(DateTime.now()),
        'collections': dump,
        'blobs': blobs,
      }),
    );
  }

  /// Remplace le contenu du profil par la sauvegarde (le compte est gardé).
  Future<void> importPlaintext(List<int> plaintext) async {
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map || decoded['collections'] is! Map) throw const BackupDecryptException();
    final current = await account();
    await store.clearAll();
    if (current != null) await _saveAccount(current);
    final collections = (decoded['collections'] as Map).cast<String, dynamic>();
    for (final entry in collections.entries) {
      if (entry.key == Col.account) continue;
      for (final record in (entry.value as List).cast<Map>()) {
        final map = record.cast<String, dynamic>();
        final id = map['id']?.toString();
        if (id != null) await store.put(entry.key, id, map);
      }
    }
    final blobs = (decoded['blobs'] as Map? ?? const {}).cast<String, dynamic>();
    for (final entry in blobs.entries) {
      await store.putBlob(entry.key, Uint8List.fromList(base64Decode(entry.value as String)));
    }
  }

  Future<BackupPayload> buildPayload(String passphrase, {required bool includeMedia}) async {
    final plaintext = await exportPlaintext(includeMedia: includeMedia);
    // 310 000 itérations PBKDF2 : calcul lourd, fait hors du fil de
    // l'interface sur Android (sur le web, WebCrypto le fait nativement).
    final payload = await compute(_encryptJob, (plaintext, passphrase));
    if (base64Decode(payload.ciphertext).length > maxBytes) throw ApiException(S.backupTooBig, statusCode: 413);
    return payload;
  }

  Future<String> backup(String passphrase, {required bool includeMedia}) async {
    final payload = await buildPayload(passphrase, includeMedia: includeMedia);
    final result = await _withDeviceAuth(() => api.putBackup(payload));
    await store.put(Col.account, metaDoc, {'id': metaDoc, 'last_backup_at': result.updatedAt});
    return result.updatedAt;
  }

  Future<void> restore(String passphrase) async {
    final payload = await _withDeviceAuth(api.getBackup);
    if (payload == null) throw ApiException(S.noBackup, statusCode: 404);
    final plaintext = await compute(_decryptJob, (payload.toJson(), passphrase));
    await importPlaintext(plaintext);
  }

  Future<void> deleteRemote() => _withDeviceAuth(api.deleteBackup);

  Future<String?> lastBackupAt() async => (await store.get(Col.account, metaDoc))?['last_backup_at'] as String?;

  /// Suppression du compte en ligne (« Supprimer toutes mes données »).
  Future<void> deleteAccount() => _withDeviceAuth(api.deleteMe);
}

final deviceAccountApiProvider = Provider<DeviceAccountApi>((ref) => DeviceAccountApi(ref.watch(dioProvider)));

/// Toujours sur le coffre RÉEL : le profil leurre n'a pas de sauvegarde.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    api: ref.watch(deviceAccountApiProvider),
    store: ref.watch(profileStoreProvider),
    tokens: ref.watch(tokenStorageProvider),
  ),
);

Future<void> trackBackup(WidgetRef ref) => ref.read(statsServiceProvider).track(StatEvent.recordBackup);

Future<BackupPayload> _encryptJob((List<int>, String) args) => BackupCrypto.encrypt(args.$1, args.$2);

Future<List<int>> _decryptJob((Map<String, dynamic>, String) args) =>
    BackupCrypto.decrypt(BackupPayload.fromJson(args.$1), args.$2);
