import '../../../core/utils/dates.dart';

/// Estimation des prochaines règles à partir des débuts de règles notés.
/// Toujours présentée comme une ESTIMATION dans l'interface.
class CycleEstimate {
  const CycleEstimate({required this.lastStart, this.averageLength, this.nextStart, this.daysLate = 0});

  final DateTime lastStart;

  /// Moyenne (arrondie) des écarts entre débuts consécutifs ; `null` s'il y a
  /// moins de deux débuts notés.
  final int? averageLength;
  final DateTime? nextStart;

  /// Jours écoulés après la date estimée (0 si pas en retard).
  final int daysLate;

  bool get isLate => daysLate > 0;
}

CycleEstimate? estimateCycle(Iterable<DateTime> starts, DateTime today) {
  final sorted = starts.map(dateOnly).toSet().toList()..sort();
  if (sorted.isEmpty) return null;
  final last = sorted.last;
  if (sorted.length < 2) return CycleEstimate(lastStart: last);
  var total = 0;
  for (var i = 1; i < sorted.length; i++) {
    total += daysBetween(sorted[i - 1], sorted[i]);
  }
  final average = (total / (sorted.length - 1)).round();
  final next = DateTime(last.year, last.month, last.day + average);
  final late = daysBetween(next, today);
  return CycleEstimate(lastStart: last, averageLength: average, nextStart: next, daysLate: late > 0 ? late : 0);
}

/// Âge de la grossesse et date prévue d'accouchement depuis le premier jour
/// des dernières règles (DDR). Estimation à confirmer par un soignant.
class PregnancyEstimate {
  const PregnancyEstimate({required this.weeks, required this.days, required this.dueDate, required this.totalDays});

  final int weeks;
  final int days;
  final DateTime dueDate;
  final int totalDays;
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Règle de Naegele : DDR + 7 jours, − 3 mois, + 1 an (le jour est ramené au
/// dernier jour du mois si besoin, ex. 31 → 30).
DateTime naegeleDueDate(DateTime lmp) {
  final plus7 = DateTime(lmp.year, lmp.month, lmp.day + 7);
  final shifted = DateTime(plus7.year + 1, plus7.month - 3, 1);
  final day = plus7.day.clamp(1, _daysInMonth(shifted.year, shifted.month));
  return DateTime(shifted.year, shifted.month, day);
}

/// `null` si la DDR est dans le futur.
PregnancyEstimate? pregnancyFromLmp(DateTime lmp, DateTime today) {
  final total = daysBetween(lmp, today);
  if (total < 0) return null;
  return PregnancyEstimate(weeks: total ~/ 7, days: total % 7, dueDate: naegeleDueDate(lmp), totalDays: total);
}

/// Jour du suivi après l'accouchement (le jour de l'accouchement = jour 0).
int postpartumDay(DateTime delivery, DateTime today) => daysBetween(delivery, today);

const postpartumFollowUpDays = 42;

/// Âge de la majorité : en dessous, le message d'alerte n'inclut jamais la
/// position, et les leçons « Adolescente » sont proposées d'abord.
const adultAge = 18;

/// Logique PURE : l'âge noté dans « Mon profil santé » (champ `age`, en
/// années) est-il inférieur à 18 ans ? Âge absent ou illisible : `false`.
bool isMinorProfile(Map<String, dynamic>? healthProfile) {
  final age = healthProfile?['age'];
  final years = age is num ? age : num.tryParse(age?.toString().replaceAll(',', '.') ?? '');
  return years != null && years >= 0 && years < adultAge;
}
