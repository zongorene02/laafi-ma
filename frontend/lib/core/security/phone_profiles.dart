import '../storage/vault.dart';
import 'pin_service.dart';
import 'secret_phrase.dart';

export 'pin_service.dart' show PhoneProfiles;

/// Premier numéro de profil libre (téléphone partagé), `null` si les 3
/// profils existent déjà.
int? nextFreeProfile(Iterable<int> existing) {
  final used = {1, ...existing};
  for (final id in PhoneProfiles.ids) {
    if (!used.contains(id)) return id;
  }
  return null;
}

/// Retire le profil 2 ou 3 d'un téléphone partagé : son code, son code de la
/// page Aide, sa phrase d'aide et son coffre (carnet, journal, contacts,
/// journal des partages) sont effacés. Le profil 1 ne se retire pas : on
/// utilise « Supprimer toutes mes données ».
Future<void> removePhoneProfile({
  required int profile,
  required PinService pins,
  required VaultService vault,
  required SecretPhraseStore phrases,
}) async {
  if (profile == 1 || !PhoneProfiles.ids.contains(profile)) {
    throw ArgumentError.value(profile, 'profile', 'seuls les profils 2 et 3 se retirent');
  }
  await pins.clear(PhoneProfiles.pinSlot(profile));
  await pins.clear(PhoneProfiles.helpSlot(profile));
  await phrases.clear(profile);
  await vault.wipe(VaultName.profile(profile));
}
