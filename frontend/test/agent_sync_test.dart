import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/core/storage/token_storage.dart';
import 'package:laafi_ma/features/agent/data/agent_repository.dart';
import 'package:laafi_ma/features/agent/data/sync_merge.dart';

import 'helpers/fake_http.dart';

Map<String, dynamic> beneficiary(String id, String updatedAt, {bool dirty = false, String pseudonym = 'A'}) => {
  'id': id,
  'pseudonym': pseudonym,
  'village': null,
  'age_range': '20-24',
  'pregnant': false,
  'expected_due_date': null,
  'children_under_5': 0,
  'consent_given_at': '2026-10-01T08:00:00Z',
  'notes': null,
  'updated_at': updatedAt,
  'deleted': false,
  if (dirty) dirtyFlag: true,
};

void main() {
  group('Fusion de la file de synchronisation', () {
    test('seuls les éléments en attente partent, sans champs locaux', () {
      final pending = pendingRecords([
        beneficiary('a', '2026-10-29T10:00:00Z', dirty: true),
        beneficiary('b', '2026-10-29T09:00:00Z'),
      ]);
      expect(pending, hasLength(1));
      expect(pending.single['id'], 'a');
      expect(pending.single.containsKey(dirtyFlag), isFalse);
    });

    test('envoyés -> propres ; reçus -> ajoutés ; dernier écrit gagnant', () {
      final local = [
        beneficiary('sent', '2026-10-29T10:00:00Z', dirty: true),
        beneficiary('newer-local', '2026-10-29T12:00:00Z', dirty: true, pseudonym: 'local'),
        beneficiary('older-local', '2026-10-29T08:00:00Z', dirty: true, pseudonym: 'local'),
        beneficiary('clean', '2026-10-28T08:00:00Z', pseudonym: 'avant'),
      ];
      final merged = mergeAfterSync(
        local: local,
        sent: [stripLocalFields(local[0])],
        server: [
          beneficiary('newer-local', '2026-10-29T11:00:00Z', pseudonym: 'serveur'),
          beneficiary('older-local', '2026-10-29T09:00:00Z', pseudonym: 'serveur'),
          beneficiary('clean', '2026-10-29T09:30:00Z', pseudonym: 'après'),
          beneficiary('from-server', '2026-10-29T09:00:00Z'),
        ],
      );
      final byId = {for (final r in merged) r['id']: r};
      expect(byId['sent']![dirtyFlag], isNull);
      expect(byId['newer-local']!['pseudonym'], 'local');
      expect(byId['newer-local']![dirtyFlag], isTrue);
      expect(byId['older-local']!['pseudonym'], 'serveur');
      expect(byId['older-local']![dirtyFlag], isNull);
      expect(byId['clean']!['pseudonym'], 'après');
      expect(byId.containsKey('from-server'), isTrue);
    });

    test('un élément modifié PENDANT l\'envoi reste en attente', () {
      final local = [beneficiary('a', '2026-10-29T10:05:00Z', dirty: true)];
      final merged = mergeAfterSync(local: local, sent: [beneficiary('a', '2026-10-29T10:00:00Z')], server: const []);
      expect(merged.single[dirtyFlag], isTrue);
    });
  });

  test('AgentRepository.sync : corps conforme à docs/API.md et état local mis à jour', () async {
    Map<String, dynamic>? body;
    final api = fakeApi((request) {
      if (request.path == '/agent/sync') {
        body = (request.data as Map).cast<String, dynamic>();
        return jsonResponse({
          'server_time': '2026-10-29T10:30:00Z',
          'beneficiaries': [beneficiary('remote', '2026-10-29T10:20:00Z', pseudonym: 'Distante')],
          'visits': [],
          'gbv_referrals': [],
        });
      }
      return emptyResponse(404);
    });
    await api.tokens.saveToken(TokenKind.staff, 'agent-token');
    final store = MemoryJsonStore();
    final repo = AgentRepository(AgentApi(api.client.dio), store);

    await repo.save(AgentCollections.beneficiaries, beneficiary('local', 'x'));
    await repo.save(AgentCollections.gbvReferrals, {
      'id': 'g1',
      'referral_date': '2026-10-29',
      'service_id': null,
      'category': 'physical',
    });
    expect(await repo.pendingCount(), 2);

    await repo.sync();

    expect(api.adapter.requests.single.headers['Authorization'], 'Bearer agent-token');
    expect(body!.keys.toSet(), {'since', 'beneficiaries', 'visits', 'gbv_referrals'});
    expect(body!['since'], isNull);
    final sentReferral = (body!['gbv_referrals'] as List).single as Map;
    expect(sentReferral.keys.toSet(), {'id', 'referral_date', 'service_id', 'category', 'updated_at'});
    expect(((body!['beneficiaries'] as List).single as Map).containsKey(dirtyFlag), isFalse);

    expect(await repo.pendingCount(), 0);
    expect(await repo.lastSync(), '2026-10-29T10:30:00Z');
    final names = (await repo.list(AgentCollections.beneficiaries)).map((b) => b['pseudonym']).toSet();
    expect(names, {'A', 'Distante'});

    // Deuxième synchro : `since` = heure serveur de la précédente.
    await repo.sync();
    expect(body!['since'], '2026-10-29T10:30:00Z');
  });

  test('le numéro d\'une bénéficiaire reste sur le téléphone : jamais dans la synchro', () async {
    String? sentJson;
    final api = fakeApi((request) {
      sentJson = jsonEncode(request.data);
      return jsonResponse({
        'server_time': '2026-10-29T10:30:00Z',
        'beneficiaries': [],
        'visits': [],
        'gbv_referrals': [],
      });
    });
    await api.tokens.saveToken(TokenKind.staff, 'agent-token');
    final repo = AgentRepository(AgentApi(api.client.dio), MemoryJsonStore());
    await repo.save(AgentCollections.beneficiaries, {
      ...beneficiary('b1', 'x'),
      'next_appointment_date': '2026-11-05',
      'next_appointment_reason': 'prenatal',
    });
    await repo.setPhone('b1', ' 70 12 34 56 ');
    expect(await repo.phoneOf('b1'), '70 12 34 56');
    expect(await repo.pendingCount(), 1);

    await repo.sync();

    final body = jsonDecode(sentJson!) as Map<String, dynamic>;
    final sent = (body['beneficiaries'] as List).single as Map;
    expect(sent['next_appointment_date'], '2026-11-05');
    expect(sent['next_appointment_reason'], 'prenatal');
    expect(sentJson, isNot(contains('70 12 34 56')));
    expect(sentJson, isNot(contains('phone')));
    expect(body.keys.toSet(), {'since', 'beneficiaries', 'visits', 'gbv_referrals'});
    // Toujours là après la synchro, et effacé avec la bénéficiaire.
    expect(await repo.phones(), {'b1': '70 12 34 56'});
    await repo.softDelete(AgentCollections.beneficiaries, (await repo.list(AgentCollections.beneficiaries)).single);
    expect(await repo.phoneOf('b1'), isNull);
    await repo.setPhone('b2', '  ');
    expect(await repo.phones(), isEmpty);
  });

  test('résumé du serveur (`GET /agent/summary`)', () async {
    final api = fakeApi(
      (_) => jsonResponse({
        'beneficiaries': 12,
        'pregnant': 4,
        'visits_last_30_days': 9,
        'referrals_last_30_days': 2,
        'danger_signs_last_30_days': 1,
      }),
    );
    final summary = await AgentApi(api.client.dio).summary();
    expect(summary.beneficiaries, 12);
    expect(summary.pregnant, 4);
    expect(summary.dangerSignsLast30Days, 1);
  });
}
