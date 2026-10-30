import '../../../core/l10n/strings.dart';
import '../../../core/utils/dates.dart';
import 'share_payload.dart';

/// Logique PURE du « Journal des partages » : un élément par QR code créé,
/// gardé dans le coffre du profil. L'application ne sait PAS si le code a été
/// lu (le téléphone du soignant le lit sans internet) : seule la création est
/// notée.
Map<String, dynamic> shareLogEntry(SharePayload payload, Iterable<String> sections, {required String id}) {
  final order = shareSections.keys.toList();
  final chosen = sections.where(order.contains).toSet().toList()..sort((a, b) => order.indexOf(a) - order.indexOf(b));
  return {
    'id': id,
    'date': isoDate(payload.generatedAt.toLocal()),
    'created_at': utcTimestamp(payload.generatedAt),
    'expires_at': utcTimestamp(payload.expiresAt),
    'sections': chosen,
  };
}

/// Nom court d'une rubrique (« Profil santé » plutôt que la phrase entière).
String shortSectionLabel(String key) => (shareSections[key] ?? key).split(' (').first;

/// « 29/10/2026 14:05 · Profil santé, Grossesse en cours · valable jusqu'à 14:20 »
String shareLogSummary(Map<String, dynamic> entry) {
  final created = parseTimestamp(entry['created_at'])?.toLocal();
  final expires = parseTimestamp(entry['expires_at'])?.toLocal();
  final sections = [for (final key in (entry['sections'] as List? ?? const [])) shortSectionLabel(key.toString())];
  return S.shareLogLine(
    created == null ? '' : '${frDate(created)} ${hhmm(created)}',
    sections.join(', '),
    expires == null ? '' : hhmm(expires),
  );
}
