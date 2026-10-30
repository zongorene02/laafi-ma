import '../data/learn_repository.dart';

/// Parcours d'où vient le « Conseil de la semaine ».
const weeklyTipTracks = {'bien_etre', 'general'};

/// Numéro de semaine ISO 8601 (1 à 53) : la semaine qui contient le jeudi.
int isoWeekNumber(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final firstOfYear = DateTime.utc(thursday.year, 1, 1);
  return thursday.difference(firstOfYear).inDays ~/ 7 + 1;
}

/// Logique PURE : une capsule VALIDÉE (déjà en cache) des parcours bien-être
/// et général, choisie selon le numéro de semaine ISO. Même semaine, même
/// conseil ; rien en cache, rien d'affiché (aucun contenu inventé).
Capsule? weeklyTip(List<Capsule> capsules, DateTime today) {
  final pool = capsules.where((c) => weeklyTipTracks.contains(c.track)).toList()
    ..sort((a, b) {
      final byTrack = a.track.compareTo(b.track);
      if (byTrack != 0) return byTrack;
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
  if (pool.isEmpty) return null;
  return pool[(isoWeekNumber(today) - 1) % pool.length];
}

/// Parcours conseillé aux moins de 18 ans.
const minorTrack = 'adolescente';

/// Logique PURE : pour une adolescente, les capsules du parcours
/// « adolescente » d'abord (l'ordre des autres ne change pas).
List<Capsule> orderForAge(List<Capsule> capsules, {required bool minor}) {
  if (!minor) return capsules;
  return [...capsules.where((c) => c.track == minorTrack), ...capsules.where((c) => c.track != minorTrack)];
}
