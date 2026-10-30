import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/storage/json_store.dart';
import '../../core/utils/dates.dart';

/// Types d'événements acceptés par `POST /events` (docs/API.md).
abstract final class StatEvent {
  static const appOpened = 'app_opened';
  static const questionAsked = 'question_asked';
  static const questionUnanswered = 'question_unanswered';
  static const dangerFlagged = 'danger_flagged';
  static const helpOpened = 'help_opened';
  static const helpCall = 'help_call';
  static const helpAlertSent = 'help_alert_sent';
  static const directoryViewed = 'directory_viewed';
  static const capsulePlayed = 'capsule_played';
  static const reminderDone = 'reminder_done';
  static const recordBackup = 'record_backup';
  static const monthlyActive = 'monthly_active';
  static const questionVoice = 'question_voice';
  static const answerUnderstood = 'answer_understood';
  static const answerNotUnderstood = 'answer_not_understood';
  static const ancVisitRecorded = 'anc_visit_recorded';
  static const vaccineRecorded = 'vaccine_recorded';
}

/// Statistiques anonymes : RIEN n'est noté si la femme n'a pas accepté.
/// Chaque événement ne porte que son type, la langue, le district choisi
/// (facultatif) et la DATE — jamais l'heure, jamais d'identifiant, jamais de
/// texte libre. Envoi par lots de 100 au plus.
class StatsService {
  StatsService({
    required this._dio,
    required this._queue,
    required this._optedIn,
    required this._lang,
    required this._districtId,
    JsonStore? meta,
    DateTime Function()? clock,
  }) : _metaStore = meta,
       _clock = clock ?? DateTime.now;

  final Dio _dio;
  final JsonStore _queue;
  final bool Function() _optedIn;
  final String Function() _lang;
  final String? Function() _districtId;

  /// Où retenir le dernier mois de `monthly_active` (coffre `meta`).
  final JsonStore? _metaStore;
  JsonStore get _meta => _metaStore ?? _queue;
  final DateTime Function() _clock;
  Future<int>? _inFlight;

  static const collection = 'events_queue';
  static const batchSize = 100;
  static const metaCollection = 'stats_meta';
  static const monthlyDoc = 'monthly_active';

  Future<void> track(String type) async {
    if (!_optedIn()) return;
    final id = const Uuid().v4();
    await _queue.put(collection, id, {
      '_id': id,
      'type': type,
      'lang': _lang(),
      'district_id': _districtId(),
      'occurred_on': isoDate(_clock()),
    });
    // Envoi opportuniste : hors connexion, l'événement attend simplement.
    flush().ignore();
  }

  /// `monthly_active` : au plus UNE fois par mois civil et par téléphone. Le
  /// téléphone retient seulement le mois (« 2026-10 ») ; aucun identifiant
  /// n'est envoyé. Renvoie `true` si l'événement a été mis en file.
  Future<bool> trackMonthlyActive() async {
    if (!_optedIn()) return false;
    final month = isoDate(_clock()).substring(0, 7);
    final last = await _meta.get(metaCollection, monthlyDoc);
    if (last?['month'] == month) return false;
    await _meta.put(metaCollection, monthlyDoc, {'month': month});
    await track(StatEvent.monthlyActive);
    return true;
  }

  /// Envoie la file par lots. Renvoie le nombre d'événements envoyés. Un
  /// appel pendant un envoi en cours attend simplement celui-ci.
  Future<int> flush() => _inFlight ??= _flush().whenComplete(() => _inFlight = null);

  Future<int> _flush() async {
    var sent = 0;
    try {
      if (!_optedIn()) {
        await _queue.clearCollection(collection);
        return 0;
      }
      final pending = await _queue.list(collection);
      for (var start = 0; start < pending.length; start += batchSize) {
        final batch = pending.sublist(start, (start + batchSize).clamp(0, pending.length));
        await _dio.post(
          '/events',
          data: {
            'events': [
              for (final e in batch)
                {
                  'type': e['type'],
                  'lang': e['lang'],
                  'district_id': e['district_id'],
                  'occurred_on': e['occurred_on'],
                },
            ],
          },
        );
        for (final e in batch) {
          await _queue.delete(collection, e['_id'] as String);
        }
        sent += batch.length;
      }
    } on DioException {
      // Pas de réseau : on réessaiera au prochain événement ou démarrage.
    }
    return sent;
  }
}

final statsServiceProvider = Provider<StatsService>((ref) {
  return StatsService(
    dio: ref.watch(dioProvider),
    queue: ref.watch(cacheStoreProvider),
    optedIn: () => ref.read(settingsProvider).statsOptIn,
    lang: () => ref.read(settingsProvider).lang,
    districtId: () => ref.read(settingsProvider).districtId,
    meta: ref.watch(metaStoreProvider),
  );
});
