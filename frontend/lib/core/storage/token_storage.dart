import 'secret_store.dart';

/// Deux jetons distincts peuvent coexister sur un même téléphone :
/// - [device] : compte anonyme `woman` (uniquement pour la sauvegarde chiffrée) ;
/// - [staff] : agent de santé connecté à l'espace agent.
/// Ils ne sont jamais mélangés : chaque requête déclare celui qu'elle utilise
/// (voir `AuthScope` dans `api_client.dart`).
enum TokenKind { device, staff }

class TokenStorage {
  TokenStorage(this._secrets);

  final SecretStore _secrets;

  String _key(TokenKind kind) => 'token_${kind.name}';

  Future<String?> readToken(TokenKind kind) => _secrets.read(_key(kind));

  Future<void> saveToken(TokenKind kind, String token) => _secrets.write(_key(kind), token);

  Future<void> clearToken(TokenKind kind) => _secrets.delete(_key(kind));
}
