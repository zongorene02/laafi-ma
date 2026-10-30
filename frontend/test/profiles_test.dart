// Téléphone partagé (jusqu'à 3 profils réels), phrase d'aide secrète par
// profil, camouflage de l'icône.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/security/icon_disguise.dart';
import 'package:laafi_ma/core/security/phone_profiles.dart';
import 'package:laafi_ma/core/security/pin_flags.dart';
import 'package:laafi_ma/core/security/pin_service.dart';
import 'package:laafi_ma/core/security/secret_phrase.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/core/storage/secret_store.dart';
import 'package:laafi_ma/core/storage/vault.dart';

void main() {
  group('Code -> profil (logique pure)', () {
    test('premier profil réel qui correspond, sinon leurre, sinon refus', () {
      expect(resolveUnlock([true, false, false], decoyMatch: false), const PinUnlock(UnlockResult.real, 1));
      expect(resolveUnlock([false, true, false], decoyMatch: false), const PinUnlock(UnlockResult.real, 2));
      expect(resolveUnlock([false, false, true], decoyMatch: false), const PinUnlock(UnlockResult.real, 3));
      expect(resolveUnlock([false, false, false], decoyMatch: true), const PinUnlock(UnlockResult.decoy));
      expect(resolveUnlock([false, false, false], decoyMatch: false), const PinUnlock(UnlockResult.invalid));
    });

    test('codes et coffres de chaque profil', () {
      expect(PhoneProfiles.ids.map(PhoneProfiles.pinSlot), [PinSlot.real, PinSlot.real2, PinSlot.real3]);
      expect(PhoneProfiles.ids.map(PhoneProfiles.helpSlot), [PinSlot.help, PinSlot.help2, PinSlot.help3]);
      // Profil 1 = coffre historique : aucune migration pour les utilisatrices existantes.
      expect(VaultName.profile(1), 'laafi_real');
      expect(VaultName.profile(1), VaultName.real);
      expect(VaultName.profile(2), 'laafi_real_2');
      expect(VaultName.profile(3), 'laafi_real_3');
      expect({for (final id in PhoneProfiles.ids) VaultName.profile(id)}, hasLength(3));
      // « Tout effacer » efface tous les profils.
      expect(VaultName.all, containsAll(['laafi_real', 'laafi_real_2', 'laafi_real_3', 'laafi_decoy']));
    });

    test('premier numéro libre', () {
      expect(nextFreeProfile(const []), 2);
      expect(nextFreeProfile(const [1]), 2);
      expect(nextFreeProfile(const [1, 3]), 2);
      expect(nextFreeProfile(const [1, 2]), 3);
      expect(nextFreeProfile(const [1, 2, 3]), isNull);
    });
  });

  group('PinService avec plusieurs profils', () {
    late MemorySecretStore secrets;
    late PinService pins;

    setUp(() {
      secrets = MemorySecretStore();
      pins = PinService(secrets, iterations: 1000);
    });

    test('chaque code ouvre SON profil ; le leurre reste le leurre', () async {
      await pins.set(PinSlot.real, '1111');
      await pins.set(PinSlot.real2, '2222');
      await pins.set(PinSlot.real3, '3333');
      await pins.set(PinSlot.decoy, '9999');
      expect(await pins.unlockProfile('1111'), const PinUnlock(UnlockResult.real, 1));
      expect(await pins.unlockProfile('2222'), const PinUnlock(UnlockResult.real, 2));
      expect(await pins.unlockProfile('3333'), const PinUnlock(UnlockResult.real, 3));
      expect(await pins.unlockProfile('9999'), const PinUnlock(UnlockResult.decoy));
      expect(await pins.unlockProfile('0000'), const PinUnlock(UnlockResult.invalid));
      expect(await pins.unlock('2222'), UnlockResult.real);
      expect(await pins.existingProfiles(), [1, 2, 3]);
    });

    test('un seul profil (utilisatrice existante) : rien ne change', () async {
      await pins.set(PinSlot.real, '4821');
      expect(await pins.unlockProfile('4821'), const PinUnlock(UnlockResult.real, 1));
      expect(await pins.existingProfiles(), [1]);
    });

    test('tous les codes du téléphone sont différents', () async {
      await pins.set(PinSlot.real, '1111');
      await pins.set(PinSlot.help, '5555');
      await expectLater(pins.set(PinSlot.real2, '1111'), throwsA(isA<PinException>()));
      await expectLater(pins.set(PinSlot.real2, '5555'), throwsA(isA<PinException>()));
      await pins.set(PinSlot.real2, '2222');
      await expectLater(pins.set(PinSlot.help2, '2222'), throwsA(isA<PinException>()));
      await expectLater(pins.set(PinSlot.decoy, '2222'), throwsA(isA<PinException>()));
      await expectLater(pins.set(PinSlot.real3, '2222'), throwsA(isA<PinException>()));
    });

    test('codes de la page Aide par profil', () async {
      await pins.set(PinSlot.real, '1111');
      await pins.set(PinSlot.real2, '2222');
      await pins.set(PinSlot.help2, '7777');
      final flags = await PinFlagsController.load(pins);
      expect(flags.profiles, {1, 2});
      expect(flags.hasHelpCodeFor(1), isFalse);
      expect(flags.hasHelpCodeFor(2), isTrue);
      expect(await pins.matches(PhoneProfiles.helpSlot(2), '7777'), isTrue);
      expect(await pins.matches(PhoneProfiles.helpSlot(1), '7777'), isFalse);
    });
  });

  group('Retirer un profil', () {
    test('efface le coffre, les codes et la phrase de CE profil seulement', () async {
      final secrets = MemorySecretStore();
      final pins = PinService(secrets, iterations: 1000);
      final phrases = SecretPhraseStore(secrets);
      final stores = <String, MemoryJsonStore>{};
      final deleted = <String>[];
      final vault = VaultService(
        secrets,
        opener: (name, key) async => stores.putIfAbsent(name, MemoryJsonStore.new),
        deleter: (name) async => deleted.add(name),
      );
      await pins.set(PinSlot.real, '1111');
      await pins.set(PinSlot.real2, '2222');
      await pins.set(PinSlot.help2, '7777');
      await phrases.write(1, 'je prépare le tô ce soir');
      await phrases.write(2, 'le riz est presque cuit');
      await (await vault.open(VaultName.profile(1))).put('journal', 'a', {'id': 'a'});
      await (await vault.open(VaultName.profile(2))).put('journal', 'b', {'id': 'b'});

      await removePhoneProfile(profile: 2, pins: pins, vault: vault, phrases: phrases);

      expect(await pins.has(PinSlot.real2), isFalse);
      expect(await pins.has(PinSlot.help2), isFalse);
      expect(await phrases.read(2), isNull);
      expect(deleted, ['laafi_real_2']);
      expect(secrets.values.containsKey(VaultService.keySecretName('laafi_real_2')), isFalse);
      expect(await stores['laafi_real_2']!.list('journal'), isEmpty);
      // Le profil 1 n'est pas touché.
      expect(await pins.unlockProfile('1111'), const PinUnlock(UnlockResult.real, 1));
      expect(await phrases.read(1), 'je prépare le tô ce soir');
      expect(await stores['laafi_real']!.list('journal'), hasLength(1));
      expect(secrets.values.containsKey(VaultService.keySecretName('laafi_real')), isTrue);
    });

    test('le profil 1 ne se retire pas', () async {
      final secrets = MemorySecretStore();
      await expectLater(
        removePhoneProfile(
          profile: 1,
          pins: PinService(secrets, iterations: 1000),
          vault: VaultService(secrets, opener: (_, _) async => MemoryJsonStore(), deleter: (_) async {}),
          phrases: SecretPhraseStore(secrets),
        ),
        throwsArgumentError,
      );
    });

    test('« Tout effacer » efface les trois profils et toutes les phrases', () async {
      final secrets = MemorySecretStore();
      final deleted = <String>[];
      final vault = VaultService(
        secrets,
        opener: (_, _) async => MemoryJsonStore(),
        deleter: (n) async => deleted.add(n),
      );
      await SecretPhraseStore(secrets).write(3, 'la sauce est prête');
      await vault.open(VaultName.profile(3));
      await vault.wipeAll();
      expect(deleted, containsAll(['laafi_real', 'laafi_real_2', 'laafi_real_3']));
      expect(secrets.values, isEmpty);
    });
  });

  group('Phrase d\'aide secrète', () {
    const phrase = 'Je prépare le tô ce soir';

    test('égale après normalisation (casse, accents, ponctuation, espaces)', () {
      expect(matchesSecretPhrase(phrase, phrase), isTrue);
      expect(matchesSecretPhrase('  je PREPARE le to,   ce soir !', phrase), isTrue);
    });

    test('mots communs >= 80 % du plus long texte', () {
      // 6 mots attendus ; un mot mal reconnu sur 6 -> 5/6 = 0,83.
      expect(matchesSecretPhrase('je prépare le tô ce matin', phrase), isTrue);
      // 4 mots communs sur 6 -> 0,67 : refusé.
      expect(matchesSecretPhrase('je cuisine le tô ce matin', phrase), isFalse);
      expect(matchesSecretPhrase('je prépare le tô ce soir là', phrase), isTrue); // 6/7 = 0,86
      expect(matchesSecretPhrase('ce soir je prépare le tô', phrase), isTrue); // ordre indifférent
      expect(matchesSecretPhrase('je prépare', phrase), isFalse);
      expect(matchesSecretPhrase('J\'ai mal au ventre ce soir', phrase), isFalse);
    });

    test('rien sans phrase, rien pour un texte vide', () {
      expect(matchesSecretPhrase(phrase, null), isFalse);
      expect(matchesSecretPhrase(phrase, '   '), isFalse);
      expect(matchesSecretPhrase('', phrase), isFalse);
      expect(matchesSecretPhrase('?!', phrase), isFalse);
    });

    test('au moins 3 mots', () {
      expect(isValidSecretPhrase('le riz'), isFalse);
      expect(isValidSecretPhrase(' ... '), isFalse);
      expect(isValidSecretPhrase('le riz brûle'), isTrue);
    });

    test('une phrase par profil, dans le stockage sécurisé', () async {
      final secrets = MemorySecretStore();
      final store = SecretPhraseStore(secrets);
      await store.write(1, '  le riz brûle  ');
      await store.write(2, 'la sauce est prête');
      expect(await store.read(1), 'le riz brûle');
      expect(await store.read(2), 'la sauce est prête');
      expect(await store.read(3), isNull);
      await store.clear(1);
      expect(await store.read(1), isNull);
      expect(await store.read(2), isNotNull);
    });
  });

  group('Icône « Calculatrice »', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(MethodChannelIconDisguise.channelName);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('hors Android : caché et sans effet', () async {
      final disguise = MethodChannelIconDisguise(isAndroid: false);
      expect(disguise.supported, isFalse);
      expect(await disguise.setDisguised(true), isFalse);
    });

    test('Android : appelle setIconDisguised(bool) sur le canal', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      final disguise = MethodChannelIconDisguise(isAndroid: true);
      expect(disguise.supported, isTrue);
      expect(await disguise.setDisguised(true), isTrue);
      expect(calls.single.method, 'setIconDisguised');
      expect(calls.single.arguments, {'disguised': true});
    });

    test('erreur de la plateforme : renvoie false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'disguise_failed'),
      );
      expect(await MethodChannelIconDisguise(isAndroid: true).setDisguised(false), isFalse);
    });
  });
}
