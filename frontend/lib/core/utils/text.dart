/// Normalisation de texte partagée (détection des signes de danger, phrase
/// d'aide secrète) : même règle partout.
library;

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', //
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ɛ': 'e', 'ẽ': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ĩ': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o', 'ɔ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ũ': 'u',
  'œ': 'oe', 'æ': 'ae', 'ÿ': 'y', 'ñ': 'n',
};

/// Minuscules, sans accents, ponctuation remplacée par des espaces.
String normalizeText(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final mapped = _accents[char] ?? char;
    buffer.write(RegExp(r'[a-z0-9]').hasMatch(mapped) ? mapped : ' ');
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
