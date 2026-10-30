import 'package:url_launcher/url_launcher.dart';

String cleanPhone(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

/// Ouvre le composeur du téléphone avec le numéro. L'application ne garde
/// aucune trace de l'appel (mais le journal d'appels du téléphone, oui).
Future<bool> callNumber(String phone) async {
  final uri = Uri(scheme: 'tel', path: cleanPhone(phone));
  try {
    return await launchUrl(uri);
  } catch (_) {
    return false;
  }
}

/// Construit l'adresse `sms:` vers un ou plusieurs destinataires avec un
/// message prêt. Le corps est encodé à la main (`%20`), car certaines
/// applications SMS affichent littéralement les `+` d'un encodage de
/// formulaire.
Uri smsUri(List<String> phones, String body) =>
    Uri.parse('sms:${phones.map(cleanPhone).join(',')}?body=${Uri.encodeComponent(body)}');

/// Ouvre l'application SMS avec le message prêt : c'est la femme qui appuie
/// sur « Envoyer ». Aucun SMS ne part tout seul.
Future<bool> openSmsComposer(List<String> phones, String body) async {
  try {
    return await launchUrl(smsUri(phones, body));
  } catch (_) {
    return false;
  }
}
