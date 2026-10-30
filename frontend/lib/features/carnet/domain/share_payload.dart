import 'dart:convert';

import '../../../core/utils/dates.dart';
import '../data/records.dart';
import 'health_calc.dart';

class SharePayloadException implements Exception {
  const SharePayloadException(this.message, {this.expired = false});

  final String message;
  final bool expired;

  @override
  String toString() => message;
}

/// Résumé COMPACT montré à un soignant par QR code. Il n'est jamais envoyé à
/// un serveur : le téléphone de l'agent le lit directement à l'écran.
///
/// Format (JSON) : `{"t":"laafi-share","v":1,"gen":ts,"exp":ts,"d":{...}}`.
/// Un code expiré est REFUSÉ par l'espace agent.
class SharePayload {
  const SharePayload({required this.generatedAt, required this.expiresAt, required this.data});

  static const type = 'laafi-share';
  static const version = 1;
  static const validity = Duration(minutes: 15);

  /// Au-delà, le QR code devient trop dense pour un appareil photo modeste.
  static const maxLength = 1800;

  factory SharePayload.create(Map<String, dynamic> data, {DateTime? now}) {
    final generated = (now ?? DateTime.now()).toUtc();
    final truncated = DateTime.utc(
      generated.year,
      generated.month,
      generated.day,
      generated.hour,
      generated.minute,
      generated.second,
    );
    return SharePayload(generatedAt: truncated, expiresAt: truncated.add(validity), data: data);
  }

  final DateTime generatedAt;
  final DateTime expiresAt;
  final Map<String, dynamic> data;

  bool isExpired(DateTime now) => now.toUtc().isAfter(expiresAt);

  String encode() => jsonEncode({
    't': type,
    'v': version,
    'gen': utcTimestamp(generatedAt),
    'exp': utcTimestamp(expiresAt),
    'd': data,
  });

  /// Lit un QR code. Lève [SharePayloadException] (avec `expired: true`) si le
  /// code a expiré, ou si ce n'est pas un code Laafi Ma.
  static SharePayload decode(String raw, {DateTime? now}) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } on FormatException {
      throw const SharePayloadException("Ce n'est pas un code Laafi Ma.");
    }
    if (decoded is! Map || decoded['t'] != type) throw const SharePayloadException("Ce n'est pas un code Laafi Ma.");
    if (decoded['v'] != version) throw const SharePayloadException('Version de code non prise en charge.');
    final generated = parseTimestamp(decoded['gen']);
    final expires = parseTimestamp(decoded['exp']);
    if (generated == null || expires == null || decoded['d'] is! Map) {
      throw const SharePayloadException('Code incomplet.');
    }
    final payload = SharePayload(
      generatedAt: generated,
      expiresAt: expires,
      data: (decoded['d'] as Map).cast<String, dynamic>(),
    );
    if (payload.isExpired(now ?? DateTime.now())) {
      throw const SharePayloadException('Ce code a expiré. Demandez à la femme d\'en créer un nouveau.', expired: true);
    }
    return payload;
  }
}

/// Rubriques que la femme peut choisir de montrer.
const shareSections = {
  'p': 'Profil santé (âge, groupe sanguin, allergies, maladies, traitements)',
  'g': 'Grossesse en cours',
  'k': 'Contraception',
  'c': 'Dernières consultations',
  'm': 'Médicaments',
  'e': 'Enfants et vaccins',
};

String? _cut(Object? value, [int max = 160]) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return text.length <= max ? text : '${text.substring(0, max)}…';
}

Map<String, dynamic> _compact(Map<String, dynamic> map) =>
    map..removeWhere((key, value) => value == null || (value is List && value.isEmpty));

/// Construit le contenu du QR à partir des collections du carnet et des
/// rubriques choisies. Clés courtes pour garder un QR lisible.
Map<String, dynamic> buildShareData(
  Map<String, List<Map<String, dynamic>>> collections,
  Set<String> sections, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  List<Map<String, dynamic>> col(String name) => sortRecords([...?collections[name]]);
  final data = <String, dynamic>{};

  if (sections.contains('p') && col(Col.healthProfile).isNotEmpty) {
    final p = col(Col.healthProfile).first;
    data['p'] = _compact({
      'age': p['age'],
      'bg': p['blood_group'] == 'unknown' ? null : p['blood_group'],
      'al': _cut(p['allergies']),
      'cc': _cut(p['chronic_conditions']),
      'ct': _cut(p['current_treatments']),
    });
  }
  if (sections.contains('g') && col(Col.pregnancy).isNotEmpty) {
    final lmp = parseDate(col(Col.pregnancy).first['lmp']);
    final estimate = lmp == null ? null : pregnancyFromLmp(lmp, now);
    if (lmp != null) {
      data['g'] = _compact({
        'lmp': isoDate(lmp),
        'edd': estimate == null ? null : isoDate(estimate.dueDate),
        'wk': estimate?.weeks,
        'pv': col(Col.prenatalVisits).where((v) => v['done'] == true).length,
      });
    }
  }
  if (sections.contains('k') && col(Col.contraception).isNotEmpty) {
    final k = col(Col.contraception).first;
    data['k'] = _compact({'m': _cut(k['method'], 60), 's': k['start_date'], 'n': k['next_renewal']});
  }
  if (sections.contains('c')) {
    data['c'] = [
      for (final c in col(Col.consultations).take(3))
        _compact({
          'd': c['date'],
          'f': _cut(c['facility'], 60),
          'r': _cut(c['reason'], 100),
          'co': _cut(c['conclusions'], 140),
          're': _cut(c['recommendations'], 140),
        }),
    ];
  }
  if (sections.contains('m')) {
    data['m'] = [
      for (final m in col(Col.medicines).take(6))
        _compact({'n': _cut(m['name'], 60), 'ds': _cut(m['dose'], 60), 't': m['times']}),
    ];
  }
  if (sections.contains('e')) {
    final vaccines = col(Col.vaccines);
    data['e'] = [
      for (final child in col(Col.children).take(4))
        _compact({
          'n': _cut(child['name'], 40),
          'b': child['birth_date'],
          'v': [
            for (final v in vaccines.where((v) => v['child_id'] == child['id']).take(12))
              _compact({'n': _cut(v['name'], 30), 'd': v['date']}),
          ],
        }),
    ];
  }
  return _compact(data);
}
