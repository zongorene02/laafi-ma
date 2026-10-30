// Logique pure des nouveautés du dossier : bien-être, conseil de la semaine,
// mineures, journal des partages, statistiques du carnet, rappels de l'agent.

import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/features/agent/data/appointment_reminders.dart';
import 'package:laafi_ma/features/carnet/domain/health_calc.dart';
import 'package:laafi_ma/features/carnet/domain/share_log.dart';
import 'package:laafi_ma/features/carnet/domain/share_payload.dart';
import 'package:laafi_ma/features/carnet/domain/wellbeing_calc.dart';
import 'package:laafi_ma/features/carnet/records/record_specs.dart';
import 'package:laafi_ma/features/learn/data/learn_repository.dart';
import 'package:laafi_ma/features/learn/domain/weekly_tip.dart';
import 'package:laafi_ma/features/stats/stats_service.dart';

import 'helpers/fake_http.dart';

Map<String, dynamic> mood(String date, String value) => {'id': date, 'date': date, 'mood': value};

Capsule capsule(String id, String track, int order) => Capsule.fromJson({
  'id': id,
  'track': track,
  'order': order,
  'translations': {
    'fr': {'title': 'Titre $id', 'text': '...'},
  },
});

void main() {
  group('Humeur basse plusieurs jours de suite', () {
    final today = DateTime(2026, 10, 29);

    test('3 jours consécutifs « pas bien » / « très mal », jusqu\'à aujourd\'hui', () {
      final moods = [mood('2026-10-29', '1'), mood('2026-10-28', '2'), mood('2026-10-27', '2')];
      expect(hasLowMoodStreak(moods, today), isTrue);
    });

    test('le dernier jour noté peut être hier', () {
      final moods = [mood('2026-10-28', '1'), mood('2026-10-27', '2'), mood('2026-10-26', '1')];
      expect(hasLowMoodStreak(moods, today), isTrue);
    });

    test('une journée « moyen » ou mieux casse la suite', () {
      final moods = [mood('2026-10-29', '1'), mood('2026-10-28', '3'), mood('2026-10-27', '2')];
      expect(hasLowMoodStreak(moods, today), isFalse);
    });

    test('un jour sans note casse la suite', () {
      final moods = [mood('2026-10-29', '1'), mood('2026-10-28', '2'), mood('2026-10-26', '2')];
      expect(hasLowMoodStreak(moods, today), isFalse);
    });

    test('moins de 3 jours notés, ou dernière note trop ancienne : rien', () {
      expect(hasLowMoodStreak([mood('2026-10-29', '1'), mood('2026-10-28', '1')], today), isFalse);
      final old = [mood('2026-10-20', '1'), mood('2026-10-19', '1'), mood('2026-10-18', '1')];
      expect(hasLowMoodStreak(old, today), isFalse);
      expect(hasLowMoodStreak(const [], today), isFalse);
    });

    test('seuls les jours les PLUS RÉCENTS comptent', () {
      final moods = [
        mood('2026-10-29', '4'),
        mood('2026-10-28', '1'),
        mood('2026-10-27', '1'),
        mood('2026-10-26', '1'),
      ];
      expect(hasLowMoodStreak(moods, today), isFalse);
    });

    test('humeurs basses = valeurs 2 et 1 de moodChoices', () {
      final labels = {for (final (value, label) in moodChoices) value: label};
      expect(lowMoodValues.map((v) => labels[v]), everyElement(isNotNull));
      expect(lowMoodValues, {'2', '1'});
    });
  });

  group('Conseil de la semaine', () {
    test('numéro de semaine ISO 8601', () {
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1); // jeudi
      expect(isoWeekNumber(DateTime(2026, 10, 29)), 44);
      expect(isoWeekNumber(DateTime(2021, 1, 3)), 53); // dimanche, semaine 53 de 2020
      expect(isoWeekNumber(DateTime(2024, 12, 30)), 1); // lundi, semaine 1 de 2025
    });

    test('capsules bien-être / général seulement, même semaine = même conseil', () {
      final capsules = [
        capsule('a', 'bien_etre', 1),
        capsule('b', 'general', 1),
        capsule('c', 'droits', 1),
        capsule('d', 'bien_etre', 2),
      ];
      final monday = weeklyTip(capsules, DateTime(2026, 10, 26))!;
      final sunday = weeklyTip(capsules, DateTime(2026, 11, 1))!;
      expect(monday.id, sunday.id);
      expect(['a', 'b', 'd'], contains(monday.id));
      // Ordre stable : bien_etre(1), bien_etre(2), general(1) ; semaine 44 -> index 43 % 3 = 1.
      expect(monday.id, 'd');
      expect(weeklyTip(capsules, DateTime(2026, 11, 2))!.id, 'b');
      // Même résultat quel que soit l'ordre reçu.
      expect(weeklyTip(capsules.reversed.toList(), DateTime(2026, 10, 26))!.id, 'd');
    });

    test('rien en cache : aucun conseil', () {
      expect(weeklyTip(const [], DateTime(2026, 10, 29)), isNull);
      expect(weeklyTip([capsule('c', 'droits', 1)], DateTime(2026, 10, 29)), isNull);
    });
  });

  group('Mineures', () {
    test('âge du profil santé < 18', () {
      expect(isMinorProfile({'age': 16}), isTrue);
      expect(isMinorProfile({'age': 17.5}), isTrue);
      expect(isMinorProfile({'age': '15'}), isTrue);
      expect(isMinorProfile({'age': 18}), isFalse);
      expect(isMinorProfile({'age': 34}), isFalse);
      expect(isMinorProfile({'age': null}), isFalse);
      expect(isMinorProfile({'age': 'je ne sais pas'}), isFalse);
      expect(isMinorProfile(null), isFalse);
    });

    test('leçons « Adolescente » d\'abord, le reste dans le même ordre', () {
      final capsules = [capsule('g', 'general', 1), capsule('t', 'adolescente', 1), capsule('b', 'bien_etre', 1)];
      expect(orderForAge(capsules, minor: true).map((c) => c.id), ['t', 'g', 'b']);
      expect(orderForAge(capsules, minor: false).map((c) => c.id), ['g', 't', 'b']);
    });
  });

  group('Journal des partages', () {
    final payload = SharePayload.create(const {}, now: DateTime.utc(2026, 10, 29, 10, 5, 30));

    test('date, rubriques choisies (ordre du formulaire) et expiration', () {
      final entry = shareLogEntry(payload, {'m', 'p', 'inconnue'}, id: 'x');
      expect(entry['id'], 'x');
      expect(entry['created_at'], '2026-10-29T10:05:30Z');
      expect(entry['expires_at'], '2026-10-29T10:20:30Z');
      expect(entry['sections'], ['p', 'm']);
      expect(entry.containsKey('date'), isTrue);
    });

    test('résumé lisible avec noms courts des rubriques', () {
      final summary = shareLogSummary(shareLogEntry(payload, {'p', 'g'}, id: 'x'));
      expect(summary, contains('Profil santé, Grossesse en cours'));
      expect(summary, contains('valable jusqu\'à'));
      expect(summary, isNot(contains('allergies')));
    });
  });

  group('Statistiques du carnet', () {
    test('visite prénatale comptée quand elle devient « faite », une seule fois', () {
      expect(ancVisitEvent(null, {'done': true}), StatEvent.ancVisitRecorded);
      expect(ancVisitEvent(null, {'done': false}), isNull);
      expect(ancVisitEvent({'done': false}, {'done': true}), StatEvent.ancVisitRecorded);
      expect(ancVisitEvent({'done': true}, {'done': true}), isNull);
    });

    test('vaccin compté à l\'ajout, pas à chaque modification', () {
      expect(vaccineEvent(null, {'name': 'X'}), StatEvent.vaccineRecorded);
      expect(vaccineEvent({'name': 'X'}, {'name': 'X', 'notes': 'n'}), isNull);
    });

    test('les rubriques visites et vaccins déclarent leur événement', () {
      expect(recordSpecs['prenatal_visits']!.statEventOf, isNotNull);
      expect(recordSpecs['vaccines']!.statEventOf, isNotNull);
    });

    test('monthly_active : au plus une fois par mois civil, sans identifiant', () async {
      var now = DateTime(2026, 10, 1, 8);
      final queue = MemoryJsonStore();
      final meta = MemoryJsonStore();
      final api = fakeApi((_) => emptyResponse(503));
      final stats = StatsService(
        dio: api.client.dio,
        queue: queue,
        meta: meta,
        optedIn: () => true,
        lang: () => 'fr',
        districtId: () => null,
        clock: () => now,
      );
      Future<int> monthly() async =>
          (await queue.list(StatsService.collection)).where((e) => e['type'] == StatEvent.monthlyActive).length;

      expect(await stats.trackMonthlyActive(), isTrue);
      now = DateTime(2026, 10, 31, 23);
      expect(await stats.trackMonthlyActive(), isFalse);
      expect(await monthly(), 1);
      expect(await meta.get(StatsService.metaCollection, StatsService.monthlyDoc), {'month': '2026-10'});

      now = DateTime(2026, 11, 2);
      expect(await stats.trackMonthlyActive(), isTrue);
      expect(await monthly(), 2);
      final event = (await queue.list(StatsService.collection)).first;
      expect(event.keys.toSet(), {'_id', 'type', 'lang', 'district_id', 'occurred_on'});
    });

    test('monthly_active : rien sans accord (et le mois n\'est pas retenu)', () async {
      final queue = MemoryJsonStore();
      final meta = MemoryJsonStore();
      final stats = StatsService(
        dio: fakeApi((_) => emptyResponse(202)).client.dio,
        queue: queue,
        meta: meta,
        optedIn: () => false,
        lang: () => 'fr',
        districtId: () => null,
      );
      expect(await stats.trackMonthlyActive(), isFalse);
      expect(await queue.list(StatsService.collection), isEmpty);
      expect(await meta.get(StatsService.metaCollection, StatsService.monthlyDoc), isNull);
    });
  });

  group('Rappels à faire (agent)', () {
    final today = DateTime(2026, 10, 29);
    Map<String, dynamic> b(String id, String? date, {bool deleted = false}) => {
      'id': id,
      'pseudonym': id,
      'next_appointment_date': date,
      'next_appointment_reason': 'prenatal',
      'deleted': deleted,
    };

    test('en retard et 7 prochains jours, le plus urgent d\'abord', () {
      final reminders = dueAppointmentReminders(
        [
          b('late', '2026-10-20'),
          b('soon', '2026-11-05'),
          b('today', '2026-10-29'),
          b('far', '2026-11-06'),
          b('none', null),
          b('gone', '2026-10-30', deleted: true),
        ],
        today,
        phones: {'soon': '70 00 00 00'},
      );
      expect(reminders.map((r) => r.id), ['late', 'today', 'soon']);
      expect(reminders.first.overdue, isTrue);
      expect(reminders.first.daysLeft, -9);
      expect(reminders[1].overdue, isFalse);
      expect(reminders.last.phone, '70 00 00 00');
      expect(reminders.first.phone, isNull);
    });

    test('SMS neutre : la date et le centre de santé, jamais le motif', () {
      final sms = appointmentReminderSms(DateTime(2026, 11, 5));
      expect(sms, contains('05/11/2026'));
      expect(sms, contains('rendez-vous au centre de santé'));
      expect(sms.toLowerCase(), isNot(contains('prénatal')));
      expect(sms.toLowerCase(), isNot(contains('grossesse')));
      expect(sms.toLowerCase(), isNot(contains('vaccin')));
    });
  });
}
