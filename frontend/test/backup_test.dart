import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/core/storage/token_storage.dart';
import 'package:laafi_ma/features/carnet/data/backup_service.dart';
import 'package:laafi_ma/features/carnet/data/records.dart';
import 'package:laafi_ma/features/carnet/domain/backup_crypto.dart';

import 'helpers/fake_http.dart';

/// Les clés exactes du corps de `PUT /records/backup` dans docs/API.md.
const contractKeys = {
  'ciphertext',
  'nonce',
  'salt',
  'kdf',
  'kdf_iterations',
  'cipher',
  'schema_version',
  'client_updated_at',
};

void main() {
  group('BackupCrypto', () {
    test('aller-retour chiffrement / déchiffrement', () async {
      final plain = utf8.encode('{"cycles":[{"start_date":"2026-10-01"}],"note":"ɔ ɛ ẽ"}');
      final payload = await BackupCrypto.encrypt(plain, 'mot de passe solide', iterations: 1000);
      expect(utf8.decode(await BackupCrypto.decrypt(payload, 'mot de passe solide')), utf8.decode(plain));
    });

    test('mauvais mot de passe refusé', () async {
      final payload = await BackupCrypto.encrypt(utf8.encode('secret'), 'bon mot de passe', iterations: 1000);
      await expectLater(BackupCrypto.decrypt(payload, 'mauvais'), throwsA(isA<BackupDecryptException>()));
    });

    test('texte chiffré modifié refusé (étiquette GCM)', () async {
      final payload = await BackupCrypto.encrypt(utf8.encode('secret'), 'bon mot de passe', iterations: 1000);
      final bytes = base64Decode(payload.ciphertext)..[0] ^= 0xff;
      final tampered = BackupPayload.fromJson({...payload.toJson(), 'ciphertext': base64Encode(bytes)});
      await expectLater(BackupCrypto.decrypt(tampered, 'bon mot de passe'), throwsA(isA<BackupDecryptException>()));
    });

    test('forme du corps conforme à docs/API.md (310 000 itérations par défaut)', () async {
      final payload = await BackupCrypto.encrypt(
        utf8.encode('x'),
        'mot de passe solide',
        now: DateTime.utc(2026, 10, 29, 10, 15),
      );
      final json = payload.toJson();
      expect(json.keys.toSet(), contractKeys);
      expect(json['kdf'], 'pbkdf2-sha256');
      expect(json['kdf_iterations'], 310000);
      expect(json['cipher'], 'aes-256-gcm');
      expect(json['schema_version'], 1);
      expect(json['client_updated_at'], '2026-10-29T10:15:00Z');
      expect(base64Decode(json['nonce'] as String), hasLength(12));
      expect(base64Decode(json['salt'] as String), hasLength(16));
      // 1 octet de données + 16 octets d'étiquette GCM.
      expect(base64Decode(json['ciphertext'] as String), hasLength(17));
      expect(await BackupCrypto.decrypt(payload, 'mot de passe solide'), utf8.encode('x'));
    });
  });

  group('BackupService avec un faux serveur', () {
    late MemoryJsonStore store;

    setUp(() async {
      store = MemoryJsonStore();
      await store.put(Col.cycles, 'c1', {'id': 'c1', 'start_date': '2026-10-01'});
      await store.putBlob('doc_1', Uint8List.fromList([1, 2, 3]));
    });

    test('compte anonyme, envoi, puis restauration', () async {
      Map<String, dynamic>? uploaded;
      final api = fakeApi((request) {
        switch ((request.method, request.path)) {
          case ('POST', '/auth/device'):
            return jsonResponse({
              'access_token': 'tok-1',
              'token_type': 'bearer',
              'account_id': 'acc-1',
              'recovery_code': 'ABCD-EFGH-IJKL-MNOP',
            }, status: 201);
          case ('PUT', '/records/backup'):
            uploaded = (request.data as Map).cast<String, dynamic>();
            return jsonResponse({'updated_at': '2026-10-29T10:15:00Z', 'size_bytes': 1234});
          case ('GET', '/records/backup'):
            return jsonResponse({...uploaded!, 'updated_at': '2026-10-29T10:15:00Z'});
        }
        return emptyResponse(404);
      });
      final service = BackupService(api: DeviceAccountApi(api.client.dio), store: store, tokens: api.tokens);

      final account = await service.createAccount();
      expect(account.recoveryCode, 'ABCD-EFGH-IJKL-MNOP');
      expect(await api.tokens.readToken(TokenKind.device), 'tok-1');

      final updatedAt = await service.backup('mot de passe solide', includeMedia: true);
      expect(updatedAt, '2026-10-29T10:15:00Z');
      final put = api.adapter.requests.firstWhere((r) => r.method == 'PUT');
      expect(put.headers['Authorization'], 'Bearer tok-1');
      expect(uploaded!.keys.toSet(), contractKeys);
      expect(uploaded!['kdf_iterations'], 310000);

      // Le serveur ne reçoit JAMAIS le carnet en clair.
      expect(jsonEncode(uploaded), isNot(contains('2026-10-01')));

      await store.clearAll();
      await service.restore('mot de passe solide');
      expect(await store.get(Col.cycles, 'c1'), {'id': 'c1', 'start_date': '2026-10-01'});
      expect(await store.getBlob('doc_1'), [1, 2, 3]);
    });

    test('jeton expiré : renouvelé avec le code de récupération puis requête rejouée', () async {
      var backupCalls = 0;
      final api = fakeApi((request) {
        if (request.path == '/auth/device/recover') {
          expect(request.data, {'account_id': 'acc-1', 'recovery_code': 'ABCD-EFGH-IJKL-MNOP'});
          return jsonResponse({'access_token': 'tok-2', 'token_type': 'bearer'});
        }
        if (request.path == '/records/backup') {
          backupCalls++;
          if (request.headers['Authorization'] != 'Bearer tok-2') {
            return jsonResponse({'detail': 'expired'}, status: 401);
          }
          return emptyResponse(404);
        }
        return emptyResponse(500);
      });
      await api.tokens.saveToken(TokenKind.device, 'tok-old');
      await store.put(Col.account, BackupService.accountDoc, {
        'id': BackupService.accountDoc,
        'account_id': 'acc-1',
        'recovery_code': 'ABCD-EFGH-IJKL-MNOP',
      });
      final service = BackupService(api: DeviceAccountApi(api.client.dio), store: store, tokens: api.tokens);
      // 404 -> aucune sauvegarde.
      await expectLater(service.restore('peu importe'), throwsA(anything));
      expect(backupCalls, 2);
      expect(await api.tokens.readToken(TokenKind.device), 'tok-2');
    });

    test('export : le compte n\'est jamais inclus, les médias sont facultatifs', () async {
      await store.put(Col.account, 'device', {'id': 'device', 'account_id': 'a', 'recovery_code': 'r'});
      final service = BackupService(
        api: DeviceAccountApi(Dio()),
        store: store,
        tokens: fakeApi((_) => emptyResponse(500)).tokens,
      );
      final withMedia = jsonDecode(utf8.decode(await service.exportPlaintext(includeMedia: true))) as Map;
      final without = jsonDecode(utf8.decode(await service.exportPlaintext(includeMedia: false))) as Map;
      expect((withMedia['collections'] as Map).containsKey(Col.account), isFalse);
      expect((withMedia['blobs'] as Map).keys, ['doc_1']);
      expect(without['blobs'], isEmpty);
    });
  });
}
