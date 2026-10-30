/// Dates au format du contrat (docs/API.md) : `YYYY-MM-DD` pour une date,
/// ISO 8601 UTC (`2026-10-29T10:15:00Z`) pour un horodatage.
String isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

DateTime? parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

/// Horodatage UTC à la seconde, avec le suffixe `Z`.
String utcTimestamp(DateTime value) {
  final utc = value.toUtc();
  return '${isoDate(utc)}T${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)}Z';
}

DateTime? parseTimestamp(Object? value) => value is String ? DateTime.tryParse(value) : null;

/// « 29/10/2026 » — format lu au Burkina Faso.
String frDate(Object? value) {
  final date = value is DateTime ? value : parseDate(value);
  if (date == null) return '';
  return '${_two(date.day)}/${_two(date.month)}/${date.year}';
}

String hhmm(DateTime value) => '${_two(value.hour)}:${_two(value.minute)}';

/// Nombre de jours ENTIERS entre deux dates (indépendant de l'heure et des
/// changements d'heure).
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

const weekdaysShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Lundi de la semaine contenant [date].
DateTime mondayOf(DateTime date) => dateOnly(date).subtract(Duration(days: date.weekday - 1));

String _two(int value) => value.toString().padLeft(2, '0');
