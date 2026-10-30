/// Logique PURE de la file de synchronisation de l'espace agent
/// (`POST /agent/sync`, dernier écrit gagnant sur `updated_at`).
///
/// En local, chaque enregistrement porte les champs du contrat plus des
/// champs techniques préfixés par `_` (`_dirty` = modifié hors connexion, pas
/// encore envoyé). Ces champs ne partent jamais au serveur.
library;

const dirtyFlag = '_dirty';

Map<String, dynamic> stripLocalFields(Map<String, dynamic> record) =>
    Map.of(record)..removeWhere((key, _) => key.startsWith('_'));

/// Enregistrements à envoyer, nettoyés de leurs champs locaux.
List<Map<String, dynamic>> pendingRecords(Iterable<Map<String, dynamic>> local) => [
  for (final r in local)
    if (r[dirtyFlag] == true) stripLocalFields(r),
];

DateTime _ts(Object? value) => DateTime.tryParse(value?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Résultat d'une fusion : la nouvelle liste locale.
///
/// 1. Les éléments ENVOYÉS ([sent]) redeviennent « propres » s'ils n'ont pas
///    été modifiés pendant l'envoi (même `updated_at`).
/// 2. Les éléments reçus du serveur remplacent la version locale, SAUF si la
///    version locale est encore en attente et plus récente : elle partira au
///    prochain envoi (dernier écrit gagnant).
List<Map<String, dynamic>> mergeAfterSync({
  required List<Map<String, dynamic>> local,
  required List<Map<String, dynamic>> sent,
  required List<Map<String, dynamic>> server,
}) {
  final byId = <String, Map<String, dynamic>>{for (final r in local) r['id'] as String: Map.of(r)};
  final sentStamp = {for (final r in sent) r['id'] as String: r['updated_at']};

  for (final entry in byId.entries) {
    final stamp = sentStamp[entry.key];
    if (stamp != null && entry.value['updated_at'] == stamp) entry.value.remove(dirtyFlag);
  }

  for (final incoming in server) {
    final id = incoming['id'] as String;
    final current = byId[id];
    final keepLocal =
        current != null &&
        current[dirtyFlag] == true &&
        _ts(current['updated_at']).isAfter(_ts(incoming['updated_at']));
    if (!keepLocal) byId[id] = stripLocalFields(incoming);
  }
  return byId.values.toList();
}
