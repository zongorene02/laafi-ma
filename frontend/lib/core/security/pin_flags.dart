import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'pin_service.dart';

/// Quels codes facultatifs existent (lu au démarrage, puis tenu à jour).
class PinFlags {
  const PinFlags({this.hasDecoy = false, this.helpCodeProfiles = const {}, this.profiles = const {1}});

  final bool hasDecoy;

  /// Profils réels qui ont un code pour la page Aide.
  final Set<int> helpCodeProfiles;

  /// Profils réels existants (téléphone partagé).
  final Set<int> profiles;

  bool hasHelpCodeFor(int profile) => helpCodeProfiles.contains(profile);
}

final initialPinFlagsProvider = Provider<PinFlags>((ref) => const PinFlags());

class PinFlagsController extends Notifier<PinFlags> {
  @override
  PinFlags build() => ref.watch(initialPinFlagsProvider);

  Future<void> refresh() async => state = await load(ref.read(pinServiceProvider));

  static Future<PinFlags> load(PinService pins) async => PinFlags(
    hasDecoy: await pins.has(PinSlot.decoy),
    helpCodeProfiles: {
      for (final id in PhoneProfiles.ids)
        if (await pins.has(PhoneProfiles.helpSlot(id))) id,
    },
    profiles: {1, ...await pins.existingProfiles()},
  );
}

final pinFlagsProvider = NotifierProvider<PinFlagsController, PinFlags>(PinFlagsController.new);
