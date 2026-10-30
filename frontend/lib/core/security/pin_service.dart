import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../storage/secret_store.dart';

/// Les codes possibles :
/// - [real] ouvre le vrai profil (profil 1) ;
/// - [decoy] (facultatif) ouvre un profil leurre vide ;
/// - [help] (facultatif) protège en plus la page Aide (module 3) du profil 1 ;
/// - [real2] / [real3] et [help2] / [help3] : mêmes codes pour les profils 2
///   et 3 d'un téléphone partagé (voir [PhoneProfiles]).
///
/// Les noms existants ne changent pas : les codes déjà enregistrés restent
/// valables sans migration.
enum PinSlot { real, decoy, help, real2, help2, real3, help3 }

enum UnlockResult { real, decoy, invalid }

/// Profils réels d'un même téléphone (téléphone partagé), 3 au plus. Chacun a
/// son code, son code de la page Aide et son coffre chiffré. Le profil 1 est
/// le profil historique (code `real`, coffre `laafi_real`).
abstract final class PhoneProfiles {
  static const max = 3;
  static const ids = [1, 2, 3];

  static PinSlot pinSlot(int profile) => switch (profile) {
    2 => PinSlot.real2,
    3 => PinSlot.real3,
    _ => PinSlot.real,
  };

  static PinSlot helpSlot(int profile) => switch (profile) {
    2 => PinSlot.help2,
    3 => PinSlot.help3,
    _ => PinSlot.help,
  };

  static bool isProfileSlot(PinSlot slot) => slot == PinSlot.real || slot == PinSlot.real2 || slot == PinSlot.real3;

  static bool isHelpSlot(PinSlot slot) => slot == PinSlot.help || slot == PinSlot.help2 || slot == PinSlot.help3;
}

/// Ce qu'ouvre un code : le profil leurre, un profil réel (numéro 1 à 3), ou
/// rien.
class PinUnlock {
  const PinUnlock(this.result, [this.profile = 1]);

  final UnlockResult result;

  /// Numéro du profil réel ouvert (1 pour le leurre et les refus).
  final int profile;

  @override
  bool operator ==(Object other) => other is PinUnlock && other.result == result && other.profile == profile;

  @override
  int get hashCode => Object.hash(result, profile);

  @override
  String toString() => 'PinUnlock($result, $profile)';
}

/// Logique PURE : [realMatches] dit, profil par profil (index 0 = profil 1),
/// si le code correspond. Les codes étant tous différents, au plus un profil
/// correspond.
PinUnlock resolveUnlock(List<bool> realMatches, {required bool decoyMatch}) {
  for (var i = 0; i < realMatches.length; i++) {
    if (realMatches[i]) return PinUnlock(UnlockResult.real, i + 1);
  }
  return decoyMatch ? const PinUnlock(UnlockResult.decoy) : const PinUnlock(UnlockResult.invalid);
}

class PinException implements Exception {
  const PinException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Gestion des codes PIN. Seule une EMPREINTE (PBKDF2-SHA256 salé) est
/// conservée, dans le stockage sécurisé du système : jamais le code lui-même.
class PinService {
  PinService(this._secrets, {this.iterations = 20000});

  final SecretStore _secrets;

  /// Volontairement plus bas que la sauvegarde (310 000) : le déverrouillage
  /// doit rester instantané sur un petit téléphone. La vraie protection de
  /// l'empreinte est le stockage sécurisé (Keystore) qui la contient.
  final int iterations;

  static final _pinFormat = RegExp(r'^\d{4,6}$');

  static bool isValidPin(String pin) => _pinFormat.hasMatch(pin);

  String _key(PinSlot slot) => 'pin_${slot.name}';

  Future<bool> has(PinSlot slot) async => (await _secrets.read(_key(slot))) != null;

  Future<void> set(PinSlot slot, String pin) async {
    if (!isValidPin(pin)) throw const PinException('format');
    for (final other in PinSlot.values) {
      if (other != slot && await matches(other, pin)) throw const PinException('duplicate');
    }
    final salt = _randomBytes(16);
    final hash = await _derive(pin, salt, iterations);
    await _secrets.write(_key(slot), 'v1\$$iterations\$${base64Encode(salt)}\$${base64Encode(hash)}');
  }

  Future<void> clear(PinSlot slot) => _secrets.delete(_key(slot));

  Future<bool> matches(PinSlot slot, String pin) async {
    final stored = await _secrets.read(_key(slot));
    if (stored == null) return false;
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[0] != 'v1') return false;
    final rounds = int.tryParse(parts[1]) ?? iterations;
    final expected = base64Decode(parts[3]);
    final actual = await _derive(pin, base64Decode(parts[2]), rounds);
    return _constantTimeEquals(expected, actual);
  }

  Future<UnlockResult> unlock(String pin) async => (await unlockProfile(pin)).result;

  /// TOUTES les empreintes sont calculées, même si la première correspond :
  /// le temps de réponse ne trahit pas quel profil (ou le leurre) s'ouvre.
  Future<PinUnlock> unlockProfile(String pin) async {
    if (!isValidPin(pin)) return const PinUnlock(UnlockResult.invalid);
    final realMatches = [for (final id in PhoneProfiles.ids) await matches(PhoneProfiles.pinSlot(id), pin)];
    final isDecoy = await matches(PinSlot.decoy, pin);
    return resolveUnlock(realMatches, decoyMatch: isDecoy);
  }

  /// Profils réels qui ont un code (le profil 1 en a toujours un après
  /// l'accueil).
  Future<List<int>> existingProfiles() async => [
    for (final id in PhoneProfiles.ids)
      if (await has(PhoneProfiles.pinSlot(id))) id,
  ];

  static Future<List<int>> _derive(String pin, List<int> salt, int rounds) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256);
    final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Freine les essais au hasard : après [maxAttempts] erreurs, chaque nouvel
/// essai doit attendre [lockout]. Remis à zéro au premier code correct.
class AttemptLimiter {
  AttemptLimiter({this.maxAttempts = 5, this.lockout = const Duration(seconds: 30), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration lockout;
  final DateTime Function() _clock;
  int _failures = 0;
  DateTime? _blockedUntil;

  /// Secondes d'attente restantes (0 = on peut essayer).
  int get secondsLeft {
    final until = _blockedUntil;
    if (until == null) return 0;
    final left = until.difference(_clock()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  bool get canTry => secondsLeft == 0;

  void recordFailure() {
    _failures++;
    if (_failures >= maxAttempts) _blockedUntil = _clock().add(lockout);
  }

  void recordSuccess() {
    _failures = 0;
    _blockedUntil = null;
  }
}
