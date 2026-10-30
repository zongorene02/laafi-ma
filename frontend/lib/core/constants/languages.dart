/// Langues servies aux utilisatrices (voir docs/API.md, `GET /languages`).
/// `en` n'existe côté serveur que comme pivot de traduction interne : il n'est
/// jamais proposé dans l'application.
class AppLanguage {
  const AppLanguage(this.code, this.name);

  final String code;
  final String name;

  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

const List<AppLanguage> kSupportedLanguages = [
  AppLanguage('fr', 'Français'),
  AppLanguage('mos', 'Mooré'),
  AppLanguage('dyu', 'Dioula'),
];

const List<String> kSupportedLanguageCodes = ['fr', 'mos', 'dyu'];

/// Aucune langue de ce projet n'est prise en charge par le clonage vocal de
/// Trad IA : la liste reste vide, l'option « Garder ma voix » ne s'affiche donc
/// jamais dans l'espace agent.
const List<String> kVoiceCloneLanguageCodes = [];

AppLanguage languageByCode(String code) =>
    kSupportedLanguages.firstWhere((lang) => lang.code == code, orElse: () => AppLanguage(code, code.toUpperCase()));
