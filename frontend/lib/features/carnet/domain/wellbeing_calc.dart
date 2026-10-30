import '../../../core/utils/dates.dart';

/// Humeurs « basses » du journal des humeurs (`moodChoices` : 2 = « Pas
/// bien », 1 = « Très mal »).
const lowMoodValues = {'2', '1'};

/// Nombre de jours consécutifs d'humeur basse qui fait proposer, doucement,
/// de parler à quelqu'un ou de respirer.
const lowMoodStreakDays = 3;

/// Logique PURE : les [days] jours notés les plus récents sont-ils des jours
/// CONSÉCUTIFS, tous d'humeur basse, le dernier étant aujourd'hui ou hier ?
///
/// Une humeur par jour (la plus récente si plusieurs). Un jour sans note
/// casse la suite : on ne devine rien.
bool hasLowMoodStreak(List<Map<String, dynamic>> moods, DateTime today, {int days = lowMoodStreakDays}) {
  final byDay = <DateTime, Map<String, dynamic>>{};
  for (final mood in moods) {
    final day = parseDate(mood['date']);
    if (day == null) continue;
    final previous = byDay[day];
    if (previous == null || '${mood['updated_at'] ?? ''}'.compareTo('${previous['updated_at'] ?? ''}') > 0) {
      byDay[day] = mood;
    }
  }
  final recent = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  if (recent.length < days) return false;
  final gap = daysBetween(recent.first, today);
  if (gap < 0 || gap > 1) return false;
  for (var i = 0; i < days; i++) {
    if (!lowMoodValues.contains(byDay[recent[i]]!['mood']?.toString())) return false;
    if (i > 0 && daysBetween(recent[i], recent[i - 1]) != 1) return false;
  }
  return true;
}
