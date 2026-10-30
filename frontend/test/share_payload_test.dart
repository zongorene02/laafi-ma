import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/features/carnet/data/records.dart';
import 'package:laafi_ma/features/carnet/domain/share_payload.dart';

void main() {
  final generated = DateTime.utc(2026, 10, 29, 10, 0, 0);

  final collections = <String, List<Map<String, dynamic>>>{
    Col.healthProfile: [
      {'id': 'p', 'age': 24, 'blood_group': 'O+', 'allergies': 'Pénicilline'},
    ],
    Col.pregnancy: [
      {'id': 'current', 'lmp': '2026-06-01'},
    ],
    Col.prenatalVisits: [
      {'id': 'v1', 'date': '2026-08-01', 'done': true},
      {'id': 'v2', 'date': '2026-11-01', 'done': false},
    ],
    Col.children: [
      {'id': 'k1', 'name': 'Awa', 'birth_date': '2024-02-10'},
    ],
    Col.vaccines: [
      {'id': 'x1', 'child_id': 'k1', 'name': 'BCG', 'date': '2024-02-11'},
      {'id': 'x2', 'child_id': 'other', 'name': 'Autre', 'date': '2024-03-01'},
    ],
    Col.consultations: [
      for (var i = 1; i <= 5; i++) {'id': 'c$i', 'date': '2026-0$i-01', 'recommendations': 'Reco $i'},
    ],
  };

  test('aller-retour et horodatage', () {
    final payload = SharePayload.create({
      'p': {'age': 24},
    }, now: generated);
    expect(payload.expiresAt, generated.add(const Duration(minutes: 15)));
    final raw = payload.encode();
    final json = jsonDecode(raw) as Map;
    expect(json['t'], 'laafi-share');
    expect(json['gen'], '2026-10-29T10:00:00Z');
    expect(json['exp'], '2026-10-29T10:15:00Z');
    final decoded = SharePayload.decode(raw, now: generated.add(const Duration(minutes: 10)));
    expect(decoded.data, {
      'p': {'age': 24},
    });
  });

  test('un code expiré est refusé', () {
    final raw = SharePayload.create({'p': {}}, now: generated).encode();
    expect(
      () => SharePayload.decode(raw, now: generated.add(const Duration(minutes: 15, seconds: 1))),
      throwsA(isA<SharePayloadException>().having((e) => e.expired, 'expired', isTrue)),
    );
    // Encore valable à la dernière seconde.
    expect(SharePayload.decode(raw, now: generated.add(const Duration(minutes: 15))).data, isNotNull);
  });

  test('un QR étranger est refusé', () {
    expect(() => SharePayload.decode('https://exemple.org'), throwsA(isA<SharePayloadException>()));
    expect(() => SharePayload.decode('{"t":"autre"}'), throwsA(isA<SharePayloadException>()));
  });

  test('seules les rubriques choisies sont partagées', () {
    final data = buildShareData(collections, {'p'}, today: DateTime(2026, 10, 29));
    expect(data.keys, ['p']);
    expect(data['p'], {'age': 24, 'bg': 'O+', 'al': 'Pénicilline'});
  });

  test('grossesse, consultations (3 dernières), enfants et leurs vaccins', () {
    final data = buildShareData(collections, {'g', 'c', 'e'}, today: DateTime(2026, 10, 29));
    expect(data['g'], {'lmp': '2026-06-01', 'edd': '2027-03-08', 'wk': 21, 'pv': 1});
    final consultations = data['c'] as List;
    expect(consultations, hasLength(3));
    expect((consultations.first as Map)['d'], '2026-05-01');
    final children = data['e'] as List;
    expect((children.single as Map)['v'], [
      {'n': 'BCG', 'd': '2024-02-11'},
    ]);
    expect(SharePayload.create(data, now: generated).encode().length, lessThan(SharePayload.maxLength));
  });
}
