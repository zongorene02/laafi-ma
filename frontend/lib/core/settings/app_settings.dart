/// Réglages GLOBAUX de l'appareil, lisibles avant le déverrouillage (il faut
/// savoir s'il faut afficher la calculatrice ou l'écran du code, et dans quelle
/// langue parler). Rangés dans le coffre chiffré `laafi_meta`.
class AppSettings {
  const AppSettings({
    this.onboarded = false,
    this.lang = 'fr',
    this.disguise = false,
    this.iconDisguise = false,
    this.statsOptIn = false,
    this.districtId,
    this.consentRecord = false,
    this.consentBackup = false,
    this.sosMessage,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    onboarded: json['onboarded'] == true,
    lang: json['lang'] as String? ?? 'fr',
    disguise: json['disguise'] == true,
    iconDisguise: json['icon_disguise'] == true,
    statsOptIn: json['stats_opt_in'] == true,
    districtId: json['district_id'] as String?,
    consentRecord: json['consent_record'] == true,
    consentBackup: json['consent_backup'] == true,
    sosMessage: json['sos_message'] as String?,
  );

  final bool onboarded;
  final String lang;
  final bool disguise;

  /// Icône et nom « Calculatrice » sur l'écran du téléphone (Android).
  final bool iconDisguise;
  final bool statsOptIn;
  final String? districtId;
  final bool consentRecord;
  final bool consentBackup;
  final String? sosMessage;

  Map<String, dynamic> toJson() => {
    'onboarded': onboarded,
    'lang': lang,
    'disguise': disguise,
    'icon_disguise': iconDisguise,
    'stats_opt_in': statsOptIn,
    'district_id': districtId,
    'consent_record': consentRecord,
    'consent_backup': consentBackup,
    'sos_message': sosMessage,
  };

  AppSettings copyWith({
    bool? onboarded,
    String? lang,
    bool? disguise,
    bool? iconDisguise,
    bool? statsOptIn,
    String? districtId,
    bool clearDistrict = false,
    bool? consentRecord,
    bool? consentBackup,
    String? sosMessage,
  }) => AppSettings(
    onboarded: onboarded ?? this.onboarded,
    lang: lang ?? this.lang,
    disguise: disguise ?? this.disguise,
    iconDisguise: iconDisguise ?? this.iconDisguise,
    statsOptIn: statsOptIn ?? this.statsOptIn,
    districtId: clearDistrict ? null : (districtId ?? this.districtId),
    consentRecord: consentRecord ?? this.consentRecord,
    consentBackup: consentBackup ?? this.consentBackup,
    sosMessage: sosMessage ?? this.sosMessage,
  );
}
