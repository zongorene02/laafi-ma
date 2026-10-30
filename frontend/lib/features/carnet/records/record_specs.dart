import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../data/records.dart';
import '../../stats/stats_service.dart';
import '../data/reminder_service.dart';
import 'record_spec.dart';

String _d(Object? iso) => frDate(iso);

String _join(List<Object?> parts) =>
    parts.where((p) => p != null && p.toString().trim().isNotEmpty).map((p) => p.toString()).join(' · ');

/// Rappel ponctuel à 8 h le jour J (ou à l'heure donnée).
DateTime? _at(Object? date, [Object? time]) {
  final day = parseDate(date);
  if (day == null) return null;
  final parts = (time is String && time.contains(':')) ? time.split(':') : const ['8', '0'];
  return DateTime(day.year, day.month, day.day, int.tryParse(parts[0]) ?? 8, int.tryParse(parts[1]) ?? 0);
}

RecordHook _onceReminder(String prefix, {String dateKey = 'date', String? timeKey, String? doneKey}) {
  return (WidgetRef ref, Map<String, dynamic> record) async {
    final service = ref.read(reminderServiceProvider);
    final key = '${prefix}_${record['id']}';
    await service.cancel(key);
    final when = _at(record[dateKey], timeKey == null ? null : record[timeKey]);
    final done = doneKey != null && record[doneKey] == true;
    if (record['reminder'] == true && when != null && !done) await service.scheduleOnce(key, when);
  };
}

RecordHook _cancelOnce(String prefix) =>
    (WidgetRef ref, Map<String, dynamic> record) =>
        ref.read(reminderServiceProvider).cancel('${prefix}_${record['id']}');

const _maxMedicineTimes = 6;

Future<void> _scheduleMedicine(WidgetRef ref, Map<String, dynamic> record) async {
  final service = ref.read(reminderServiceProvider);
  for (var i = 0; i < _maxMedicineTimes; i++) {
    await service.cancel('med_${record['id']}_$i');
  }
  if (record['reminder'] != true) return;
  final end = parseDate(record['end_date']);
  if (end != null && daysBetween(DateTime.now(), end) < 0) return;
  final times = (record['times'] as List? ?? const []).take(_maxMedicineTimes).toList();
  for (var i = 0; i < times.length; i++) {
    final parts = times[i].toString().split(':');
    if (parts.length != 2) continue;
    await service.scheduleDaily('med_${record['id']}_$i', int.tryParse(parts[0]) ?? 8, int.tryParse(parts[1]) ?? 0);
  }
}

Future<void> _cancelMedicine(WidgetRef ref, Map<String, dynamic> record) async {
  for (var i = 0; i < _maxMedicineTimes; i++) {
    await ref.read(reminderServiceProvider).cancel('med_${record['id']}_$i');
  }
}

const _reminderField = FieldSpec('reminder', 'Me le rappeler', kind: FieldKind.toggle);

/// `anc_visit_recorded` : une visite prénatale notée « faite » (nouvelle, ou
/// qui vient de passer de « prévue » à « faite »). Une visite seulement
/// prévue, ou modifiée une deuxième fois, ne compte pas.
String? ancVisitEvent(Map<String, dynamic>? before, Map<String, dynamic> after) =>
    after['done'] == true && before?['done'] != true ? StatEvent.ancVisitRecorded : null;

/// `vaccine_recorded` : un vaccin reçu ajouté au carnet d'un enfant (pas à
/// chaque modification).
String? vaccineEvent(Map<String, dynamic>? before, Map<String, dynamic> after) =>
    before == null ? StatEvent.vaccineRecorded : null;

final Map<String, RecordSpec> recordSpecs = {
  for (final spec in <RecordSpec>[
    RecordSpec(
      id: Col.healthProfile,
      collection: Col.healthProfile,
      title: S.healthProfile,
      icon: Icons.person_rounded,
      color: AppTheme.sky,
      listenText: 'Votre profil santé : âge, groupe sanguin, allergies, maladies et traitements.',
      single: true,
      fields: const [
        FieldSpec('age', 'Âge (ans)', kind: FieldKind.number),
        FieldSpec(
          'blood_group',
          'Groupe sanguin',
          kind: FieldKind.choice,
          choices: [
            ('A+', 'A+'), ('A-', 'A−'), ('B+', 'B+'), ('B-', 'B−'), //
            ('AB+', 'AB+'), ('AB-', 'AB−'), ('O+', 'O+'), ('O-', 'O−'), ('unknown', 'Je ne sais pas'),
          ],
        ),
        FieldSpec('allergies', 'Allergies', kind: FieldKind.multiline),
        FieldSpec('chronic_conditions', 'Maladies de longue durée', kind: FieldKind.multiline),
        FieldSpec('current_treatments', 'Traitements en cours', kind: FieldKind.multiline),
      ],
      titleOf: (r) => S.healthProfile,
      subtitleOf: (r) => _join([r['age'] == null ? null : '${r['age']} ans', r['blood_group']]),
    ),
    RecordSpec(
      id: Col.cycles,
      collection: Col.cycles,
      title: S.cycle,
      icon: Icons.water_drop_rounded,
      color: AppTheme.danger,
      listenText: 'Notez le premier jour de vos règles. Le téléphone estime les prochaines.',
      fields: const [
        FieldSpec('start_date', 'Premier jour des règles', kind: FieldKind.date, required: true),
        FieldSpec('end_date', 'Dernier jour (facultatif)', kind: FieldKind.date),
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline),
      ],
      titleOf: (r) => 'Règles du ${_d(r['start_date'])}',
      subtitleOf: (r) => r['end_date'] == null ? '' : 'Jusqu\'au ${_d(r['end_date'])}',
    ),
    RecordSpec(
      id: Col.contraception,
      collection: Col.contraception,
      title: S.contraception,
      icon: Icons.medication_liquid_rounded,
      color: AppTheme.plum,
      listenText: 'Notez votre méthode, la date de début et la date du prochain renouvellement.',
      remindable: true,
      fields: const [
        FieldSpec('method', 'Méthode', required: true, hint: 'Comme indiqué par votre soignant'),
        FieldSpec('start_date', 'Date de début', kind: FieldKind.date),
        FieldSpec('next_renewal', 'Prochain renouvellement', kind: FieldKind.date),
        _reminderField,
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline),
      ],
      titleOf: (r) => r['method']?.toString() ?? S.contraception,
      subtitleOf: (r) => _join([
        r['start_date'] == null ? null : 'Depuis le ${_d(r['start_date'])}',
        r['next_renewal'] == null ? null : 'Renouveler le ${_d(r['next_renewal'])}',
      ]),
      onSaved: _onceReminder('contra', dateKey: 'next_renewal'),
      onDeleted: _cancelOnce('contra'),
    ),
    RecordSpec(
      id: Col.prenatalVisits,
      collection: Col.prenatalVisits,
      title: S.prenatalVisits,
      icon: Icons.pregnant_woman_rounded,
      color: AppTheme.terracotta,
      listenText: 'Vos visites prénatales : prévues ou faites.',
      remindable: true,
      fields: const [
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec('done', 'Visite faite', kind: FieldKind.toggle),
        FieldSpec('facility', 'Centre de santé'),
        _reminderField,
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline, privateListen: true),
      ],
      titleOf: (r) => 'Visite du ${_d(r['date'])}',
      subtitleOf: (r) => _join([r['done'] == true ? 'Faite' : 'Prévue', r['facility']]),
      onSaved: _onceReminder('visit', doneKey: 'done'),
      onDeleted: _cancelOnce('visit'),
      statEventOf: ancVisitEvent,
    ),
    RecordSpec(
      id: Col.exams,
      collection: Col.exams,
      title: S.exams,
      icon: Icons.biotech_rounded,
      color: AppTheme.sky,
      listenText: 'Vos examens et leurs résultats.',
      fields: const [
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec('name', 'Examen', required: true),
        FieldSpec('result', 'Résultat', kind: FieldKind.multiline, privateListen: true),
      ],
      titleOf: (r) => r['name']?.toString() ?? S.exams,
      subtitleOf: (r) => _d(r['date']),
    ),
    RecordSpec(
      id: Col.weights,
      collection: Col.weights,
      title: S.weight,
      icon: Icons.monitor_weight_rounded,
      color: AppTheme.leaf,
      listenText: 'Notez votre poids avec la date.',
      fields: const [
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec('weight_kg', 'Poids (kg)', kind: FieldKind.number, required: true),
      ],
      titleOf: (r) => '${r['weight_kg'] ?? ''} kg',
      subtitleOf: (r) => _d(r['date']),
    ),
    RecordSpec(
      id: Col.bloodPressure,
      collection: Col.bloodPressure,
      title: S.bloodPressure,
      icon: Icons.favorite_rounded,
      color: AppTheme.danger,
      listenText: 'Notez votre tension mesurée par le soignant, avec la date.',
      fields: const [
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec('systolic', 'Chiffre du haut', kind: FieldKind.number, required: true),
        FieldSpec('diastolic', 'Chiffre du bas', kind: FieldKind.number, required: true),
      ],
      titleOf: (r) => '${r['systolic'] ?? ''} / ${r['diastolic'] ?? ''}',
      subtitleOf: (r) => _d(r['date']),
    ),
    RecordSpec(
      id: Col.postpartumLogs,
      collection: Col.postpartumLogs,
      title: S.postpartumLogs,
      icon: Icons.child_friendly_rounded,
      color: AppTheme.terracotta,
      listenText: 'Chaque jour : allaitement et humeur.',
      fields: const [
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec(
          'breastfeeding',
          'Allaitement',
          kind: FieldKind.choice,
          choices: [('yes', 'Oui'), ('partial', 'Un peu'), ('no', 'Non')],
        ),
        FieldSpec('mood', 'Humeur', kind: FieldKind.choice, choices: moodChoices),
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline),
      ],
      titleOf: (r) => _d(r['date']),
      subtitleOf: (r) => _join([
        r['breastfeeding'] == null ? null : 'Allaitement : ${_choice(moodLessBreastfeeding, r['breastfeeding'])}',
        r['mood'] == null ? null : _choice(moodChoices, r['mood']),
      ]),
    ),
    RecordSpec(
      id: Col.children,
      collection: Col.children,
      title: S.children,
      icon: Icons.child_care_rounded,
      color: AppTheme.amber,
      listenText: 'Vos enfants. Touchez un enfant pour voir ses vaccins.',
      fields: const [
        FieldSpec('name', 'Prénom ou surnom', required: true),
        FieldSpec('birth_date', 'Date de naissance', kind: FieldKind.date),
        FieldSpec('sex', 'Sexe', kind: FieldKind.choice, choices: [('f', 'Fille'), ('m', 'Garçon')]),
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline),
      ],
      titleOf: (r) => r['name']?.toString() ?? '',
      subtitleOf: (r) => r['birth_date'] == null ? '' : 'Né(e) le ${_d(r['birth_date'])}',
    ),
    RecordSpec(
      id: Col.vaccines,
      collection: Col.vaccines,
      title: S.vaccines,
      icon: Icons.vaccines_rounded,
      color: AppTheme.leaf,
      listenText: S.vaccinesNote,
      note: S.vaccinesNote,
      parentKey: 'child_id',
      remindable: true,
      fields: const [
        FieldSpec('name', 'Vaccin (comme écrit sur le carnet)', required: true),
        FieldSpec('date', 'Date du vaccin', kind: FieldKind.date, required: true),
        FieldSpec('next_date', 'Prochain rendez-vous (si donné)', kind: FieldKind.date),
        _reminderField,
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline),
      ],
      titleOf: (r) => r['name']?.toString() ?? '',
      subtitleOf: (r) => _join([_d(r['date']), r['next_date'] == null ? null : 'Prochain : ${_d(r['next_date'])}']),
      onSaved: _onceReminder('vacc', dateKey: 'next_date'),
      onDeleted: _cancelOnce('vacc'),
      statEventOf: vaccineEvent,
    ),
    RecordSpec(
      id: Col.consultations,
      collection: Col.consultations,
      title: S.consultations,
      icon: Icons.medical_services_rounded,
      color: AppTheme.sky,
      listenText: 'Vos consultations. Touchez-en une pour écouter les recommandations.',
      fields: const [
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec('facility', 'Centre de santé'),
        FieldSpec('caregiver', 'Soignant'),
        FieldSpec('reason', 'Motif', kind: FieldKind.multiline, privateListen: true),
        FieldSpec('conclusions', 'Conclusions', kind: FieldKind.multiline, privateListen: true),
        FieldSpec('recommendations', S.recommendations, kind: FieldKind.multiline, privateListen: true),
      ],
      titleOf: (r) => 'Consultation du ${_d(r['date'])}',
      subtitleOf: (r) => _join([r['facility'], r['caregiver']]),
    ),
    RecordSpec(
      id: Col.medicines,
      collection: Col.medicines,
      title: S.medicines,
      icon: Icons.medication_rounded,
      color: AppTheme.plum,
      listenText: 'Vos médicaments et les heures où les prendre.',
      remindable: true,
      fields: const [
        FieldSpec('name', 'Médicament', required: true),
        FieldSpec('dose', 'Dose (comme sur l\'ordonnance)'),
        FieldSpec('times', 'Heures de prise', kind: FieldKind.times),
        FieldSpec('start_date', 'Début', kind: FieldKind.date),
        FieldSpec('end_date', 'Fin', kind: FieldKind.date),
        _reminderField,
      ],
      titleOf: (r) => r['name']?.toString() ?? '',
      subtitleOf: (r) => _join([r['dose'], (r['times'] as List? ?? const []).join(', ')]),
      onSaved: _scheduleMedicine,
      onDeleted: _cancelMedicine,
    ),
    RecordSpec(
      id: Col.agenda,
      collection: Col.agenda,
      title: S.agenda,
      icon: Icons.event_rounded,
      color: AppTheme.leaf,
      listenText: 'Votre agenda : rendez-vous et choses à faire pour votre santé.',
      remindable: true,
      fields: const [
        FieldSpec(
          'kind',
          'Type',
          kind: FieldKind.choice,
          choices: [('appointment', 'Rendez-vous'), ('task', 'À faire')],
        ),
        FieldSpec('title', 'Quoi ?', required: true),
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec('time', 'Heure', kind: FieldKind.time),
        FieldSpec('done', 'Fait', kind: FieldKind.toggle),
        _reminderField,
      ],
      titleOf: (r) => r['title']?.toString() ?? '',
      subtitleOf: (r) => _join([_d(r['date']), r['time'], r['done'] == true ? 'Fait' : null]),
      onSaved: _onceReminder('agenda', timeKey: 'time', doneKey: 'done'),
      onDeleted: _cancelOnce('agenda'),
    ),
    RecordSpec(
      id: Col.moods,
      collection: Col.moods,
      title: S.wellbeing,
      icon: Icons.self_improvement_rounded,
      color: AppTheme.leaf,
      listenText: S.moodToday,
      fields: const [
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true),
        FieldSpec('mood', 'Humeur', kind: FieldKind.choice, choices: moodChoices, required: true),
        FieldSpec('notes', 'Notes', kind: FieldKind.multiline),
      ],
      titleOf: (r) => _choice(moodChoices, r['mood']),
      subtitleOf: (r) => _d(r['date']),
    ),
    RecordSpec(
      id: Col.contacts,
      collection: Col.contacts,
      title: S.trustedContacts,
      icon: Icons.people_alt_rounded,
      color: AppTheme.sky,
      listenText: 'Jusqu\'à trois personnes de confiance. Elles recevront votre message d\'alerte.',
      maxItems: 3,
      fields: const [
        FieldSpec('name', S.contactName, required: true),
        FieldSpec('phone', S.contactPhone, required: true),
      ],
      titleOf: (r) => r['name']?.toString() ?? '',
      subtitleOf: (r) => r['phone']?.toString() ?? '',
    ),
  ])
    spec.id: spec,
};

const moodChoices = [
  ('5', '😀 Très bien'),
  ('4', '🙂 Bien'),
  ('3', '😐 Moyen'),
  ('2', '🙁 Pas bien'),
  ('1', '😢 Très mal'),
];

const moodLessBreastfeeding = [('yes', 'oui'), ('partial', 'un peu'), ('no', 'non')];

String _choice(List<(String, String)> choices, Object? value) =>
    choices.firstWhere((c) => c.$1 == value, orElse: () => ('', value?.toString() ?? '')).$2;
