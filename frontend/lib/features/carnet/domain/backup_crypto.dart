import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../../core/utils/dates.dart';

class BackupDecryptException implements Exception {
  const BackupDecryptException();

  @override
  String toString() => 'Mot de passe incorrect ou sauvegarde abîmée.';
}

/// Corps de `PUT /records/backup` (docs/API.md), champ pour champ.
class BackupPayload {
  const BackupPayload({
    required this.ciphertext,
    required this.nonce,
    required this.salt,
    required this.kdfIterations,
    required this.clientUpdatedAt,
    this.kdf = 'pbkdf2-sha256',
    this.cipher = 'aes-256-gcm',
    this.schemaVersion = 1,
    this.updatedAt,
  });

  factory BackupPayload.fromJson(Map<String, dynamic> json) => BackupPayload(
    ciphertext: json['ciphertext'] as String,
    nonce: json['nonce'] as String,
    salt: json['salt'] as String,
    kdf: json['kdf'] as String? ?? 'pbkdf2-sha256',
    kdfIterations: (json['kdf_iterations'] as num).toInt(),
    cipher: json['cipher'] as String? ?? 'aes-256-gcm',
    schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
    clientUpdatedAt: json['client_updated_at'] as String? ?? '',
    updatedAt: json['updated_at'] as String?,
  );

  /// Base64 de (texte chiffré ‖ étiquette GCM de 16 octets), comme WebCrypto.
  final String ciphertext;
  final String nonce;
  final String salt;
  final String kdf;
  final int kdfIterations;
  final String cipher;
  final int schemaVersion;
  final String clientUpdatedAt;

  /// Renvoyé par `GET /records/backup` uniquement.
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'nonce': nonce,
    'salt': salt,
    'kdf': kdf,
    'kdf_iterations': kdfIterations,
    'cipher': cipher,
    'schema_version': schemaVersion,
    'client_updated_at': clientUpdatedAt,
  };
}

/// Chiffrement de la sauvegarde SUR LE TÉLÉPHONE : clé dérivée du mot de passe
/// choisi par la femme (PBKDF2-SHA256, 310 000 itérations, sel aléatoire de
/// 16 octets), puis AES-256-GCM (nonce aléatoire de 12 octets). Le serveur ne
/// reçoit que le résultat opaque, jamais le mot de passe.
abstract final class BackupCrypto {
  static const defaultIterations = 310000;
  static const _macLength = 16;

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt, int iterations) {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static List<int> _random(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Future<BackupPayload> encrypt(
    List<int> plaintext,
    String passphrase, {
    int iterations = defaultIterations,
    DateTime? now,
  }) async {
    final salt = _random(16);
    final nonce = _random(12);
    final key = await _deriveKey(passphrase, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(plaintext, secretKey: key, nonce: nonce);
    return BackupPayload(
      ciphertext: base64Encode([...box.cipherText, ...box.mac.bytes]),
      nonce: base64Encode(nonce),
      salt: base64Encode(salt),
      kdfIterations: iterations,
      clientUpdatedAt: utcTimestamp(now ?? DateTime.now()),
    );
  }

  static Future<List<int>> decrypt(BackupPayload payload, String passphrase) async {
    if (payload.kdf != 'pbkdf2-sha256' || payload.cipher != 'aes-256-gcm') throw const BackupDecryptException();
    try {
      final all = base64Decode(payload.ciphertext);
      if (all.length < _macLength) throw const BackupDecryptException();
      final key = await _deriveKey(passphrase, base64Decode(payload.salt), payload.kdfIterations);
      final box = SecretBox(
        all.sublist(0, all.length - _macLength),
        nonce: base64Decode(payload.nonce),
        mac: Mac(all.sublist(all.length - _macLength)),
      );
      return await AesGcm.with256bits().decrypt(box, secretKey: key);
    } on SecretBoxAuthenticationError {
      throw const BackupDecryptException();
    } on FormatException {
      throw const BackupDecryptException();
    }
  }
}
