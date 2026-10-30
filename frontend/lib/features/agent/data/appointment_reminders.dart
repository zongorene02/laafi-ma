import '../../../core/l10n/strings.dart';
import '../../../core/utils/dates.dart';

/// Un rendez-vous à rappeler (« Rappels à faire » de l'espace agent).
class AppointmentReminder {
  const AppointmentReminder({required this.beneficiary, required this.date, required this.daysLeft, this.phone});

  final Map<String, dynamic> beneficiary;
  final DateTime date;

  /// Négatif : en retard de ce nombre de jours.
  final int daysLeft;

  /// Numéro noté par l'agent, gardé SEULEMENT sur son téléphone.
  final String? phone;

  bool get overdue => daysLeft < 0;
  String get id => beneficiary['id'] as String;
}

/// Logique PURE : bénéficiaires dont le prochain rendez-vous est passé (en
/// retard) ou tombe dans les [horizonDays] prochains jours, le plus urgent
/// d'abord.
List<AppointmentReminder> dueAppointmentReminders(
  Iterable<Map<String, dynamic>> beneficiaries,
  DateTime today, {
  int horizonDays = 7,
  Map<String, String> phones = const {},
}) {
  final result = <AppointmentReminder>[];
  for (final b in beneficiaries) {
    if (b['deleted'] == true) continue;
    final date = parseDate(b['next_appointment_date']);
    if (date == null) continue;
    final left = daysBetween(today, date);
    if (left > horizonDays) continue;
    result.add(AppointmentReminder(beneficiary: b, date: date, daysLeft: left, phone: phones[b['id']]));
  }
  return result..sort((a, b) => a.date.compareTo(b.date));
}

/// SMS de rappel NEUTRE : la date et « rendez-vous au centre de santé »,
/// jamais le motif ni aucun détail de santé (le téléphone peut être lu par
/// quelqu'un d'autre).
String appointmentReminderSms(DateTime date) => S.reminderSms(frDate(date));
