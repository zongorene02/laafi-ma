import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/security/calculator_engine.dart';
import 'package:laafi_ma/core/security/pin_service.dart';
import 'package:laafi_ma/core/storage/secret_store.dart';

void main() {
  group('PinService', () {
    late MemorySecretStore secrets;
    late PinService pins;

    setUp(() {
      secrets = MemorySecretStore();
      pins = PinService(secrets, iterations: 1000);
    });

    test('le code n\'est jamais stocké en clair', () async {
      await pins.set(PinSlot.real, '4821');
      expect(secrets.values.values.any((v) => v.contains('4821')), isFalse);
      expect(secrets.values['pin_real'], startsWith('v1\$1000\$'));
    });

    test('vrai code -> profil réel, leurre -> profil leurre, autre -> refus', () async {
      await pins.set(PinSlot.real, '4821');
      await pins.set(PinSlot.decoy, '1111');
      expect(await pins.unlock('4821'), UnlockResult.real);
      expect(await pins.unlock('1111'), UnlockResult.decoy);
      expect(await pins.unlock('0000'), UnlockResult.invalid);
      expect(await pins.unlock('12'), UnlockResult.invalid);
    });

    test('sans code leurre, seul le vrai code ouvre', () async {
      await pins.set(PinSlot.real, '123456');
      expect(await pins.has(PinSlot.decoy), isFalse);
      expect(await pins.unlock('123456'), UnlockResult.real);
      expect(await pins.unlock('1234'), UnlockResult.invalid);
    });

    test('format 4 à 6 chiffres', () async {
      expect(PinService.isValidPin('123'), isFalse);
      expect(PinService.isValidPin('1234567'), isFalse);
      expect(PinService.isValidPin('12a4'), isFalse);
      expect(PinService.isValidPin('0000'), isTrue);
      await expectLater(pins.set(PinSlot.real, '12'), throwsA(isA<PinException>()));
    });

    test('les trois codes doivent être différents', () async {
      await pins.set(PinSlot.real, '4821');
      await expectLater(pins.set(PinSlot.decoy, '4821'), throwsA(isA<PinException>()));
      await pins.set(PinSlot.help, '7777');
      await expectLater(pins.set(PinSlot.decoy, '7777'), throwsA(isA<PinException>()));
      expect(await pins.matches(PinSlot.help, '7777'), isTrue);
    });

    test('retirer le code leurre', () async {
      await pins.set(PinSlot.real, '4821');
      await pins.set(PinSlot.decoy, '1111');
      await pins.clear(PinSlot.decoy);
      expect(await pins.unlock('1111'), UnlockResult.invalid);
    });
  });

  group('AttemptLimiter', () {
    test('bloque après 5 erreurs, puis débloque après l\'attente', () {
      var now = DateTime(2026, 10, 29, 10);
      final limiter = AttemptLimiter(clock: () => now);
      for (var i = 0; i < 4; i++) {
        limiter.recordFailure();
      }
      expect(limiter.canTry, isTrue);
      limiter.recordFailure();
      expect(limiter.canTry, isFalse);
      expect(limiter.secondsLeft, 30);
      now = now.add(const Duration(seconds: 31));
      expect(limiter.canTry, isTrue);
      limiter.recordSuccess();
      limiter.recordFailure();
      expect(limiter.canTry, isTrue);
    });
  });

  group('Calculatrice de camouflage', () {
    String? type(CalculatorEngine engine, String keys) {
      String? candidate;
      for (final key in keys.split(' ')) {
        candidate = engine.press(key);
      }
      return candidate;
    }

    test('calcule vraiment', () {
      final engine = CalculatorEngine();
      expect(type(engine, '1 2 + 3 0 ='), isNull);
      expect(engine.display, '42');
      type(engine, '7 × 6 − 2 =');
      expect(engine.display, '40');
      type(engine, '1 0 ÷ 4 =');
      expect(engine.display, '2.5');
      type(engine, '5 ÷ 0 =');
      expect(engine.display, 'Erreur');
      type(engine, 'C 1 . 5 + 1 . 2 5 =');
      expect(engine.display, '2.75');
    });

    test('code puis « = » propose le code', () {
      final engine = CalculatorEngine();
      expect(type(engine, '4 8 2 1 ='), '4821');
      expect(engine.display, '4821');
    });

    test('pas de code après un opérateur ni hors 4-6 chiffres', () {
      final engine = CalculatorEngine();
      expect(type(engine, '4 8 + 2 1 ='), isNull);
      expect(type(engine, '1 2 3 ='), isNull);
      expect(type(engine, '1 2 3 4 5 6 7 ='), isNull);
      expect(type(engine, '1 . 2 3 4 ='), isNull);
    });

    test('effacement pris en compte', () {
      final engine = CalculatorEngine();
      expect(type(engine, '4 8 2 9 ⌫ 1 ='), '4821');
      expect(type(engine, '9 9 C 4 8 2 1 ='), '4821');
    });

    test('déverrouillage complet : calculatrice + PinService', () async {
      final pins = PinService(MemorySecretStore(), iterations: 1000);
      await pins.set(PinSlot.real, '4821');
      await pins.set(PinSlot.decoy, '2580');
      final engine = CalculatorEngine();
      Future<UnlockResult?> tryKeys(String keys) async {
        final candidate = type(engine, keys);
        return candidate == null ? null : pins.unlock(candidate);
      }

      expect(await tryKeys('1 2 + 3 ='), isNull);
      expect(await tryKeys('1 2 3 4 ='), UnlockResult.invalid);
      expect(await tryKeys('4 8 2 1 ='), UnlockResult.real);
      expect(await tryKeys('2 5 8 0 ='), UnlockResult.decoy);
    });
  });
}
