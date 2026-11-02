import '../../../core/utils/text.dart';
import 'assistant_models.dart';

export '../../../core/utils/text.dart' show normalizeText;

/// Détection HORS CONNEXION des signes de danger dans une question écrite en
/// français, avec les mots-clés téléchargés depuis l'API.
///
/// Un mot-clé correspond s'il apparaît au DÉBUT d'un mot (« saigne » trouve
/// « saignements ») : assez souple pour les variantes, sans déclencher sur un
/// fragment au milieu d'un autre mot.
List<DangerSign> detectDangerSigns(String text, List<DangerSign> signs) {
  final haystack = ' ${normalizeText(text)} ';
  if (haystack.trim().isEmpty) return const [];
  return [
    for (final sign in signs)
      if (sign.keywords.any((keyword) {
        final needle = normalizeText(keyword);
        return needle.isNotEmpty && haystack.contains(' $needle');
      }))
        sign,
  ];
}

/// Questions de la FAQ en cache les plus proches d'une question tapée, par
/// nombre de mots communs (mots de 4 lettres ou plus). Simple aide à la
/// navigation hors connexion : jamais présentée comme « la » réponse.
List<FaqEntry> closestFaqEntries(String text, List<FaqEntry> entries, {int limit = 3}) {
  final words = normalizeText(text).split(' ').where((w) => w.length >= 4).toSet();
  if (words.isEmpty) return const [];
  final scored = <(FaqEntry, int)>[];
  for (final entry in entries) {
    final question = ' ${normalizeText(entry.question)} ';
    final score = words.where((w) => question.contains(' ${w.substring(0, w.length > 6 ? 6 : w.length)}')).length;
    if (score > 0) scored.add((entry, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.take(limit).map((e) => e.$1).toList();
}
