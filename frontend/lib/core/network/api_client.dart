import 'dart:convert';

import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// URL de base de `core-service`. Redéfinissable au lancement avec
/// `--dart-define=API_BASE_URL=http://10.0.2.2:8000` (émulateur Android,
/// où `127.0.0.1` désigne l'émulateur lui-même, pas la machine hôte) ou
/// l'adresse d'un serveur distant une fois déployé.
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');

/// Erreur normalisée : chaque écran affiche `ApiException.message` sans se
/// soucier de savoir si l'échec vient du réseau, d'une réponse HTTP d'erreur,
/// ou d'un timeout — un seul type d'erreur à gérer côté UI.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// L'utilisateur a lui-même annulé l'opération : ce n'est PAS une erreur.
/// Un type distinct permet aux écrans de revenir simplement à l'état initial,
/// au lieu d'afficher un bandeau rouge pour une action volontaire.
class RequestCancelledException implements Exception {
  const RequestCancelledException();

  @override
  String toString() => 'Opération annulée';
}

/// Jeton à joindre à une requête. Déclaré PAR REQUÊTE (dans
/// `Options.extra`) plutôt que deviné d'après le chemin : le compte anonyme
/// d'une femme et la session d'un agent ne doivent jamais se mélanger.
enum AuthScope { none, device, staff }

const String authScopeKey = 'auth_scope';

Options scoped(AuthScope scope, {Options? base}) =>
    (base ?? Options()).copyWith(extra: {...?base?.extra, authScopeKey: scope});

/// Client HTTP partagé par toute l'application :
/// - joint le bon jeton selon l'[AuthScope] demandé ;
/// - transforme les erreurs Dio en `ApiException` lisibles.
class ApiClient {
  ApiClient(this._tokenStorage, {this.onStaffUnauthorized, Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              // La transcription et la synthèse vocale sont lentes sur un
              // serveur sans carte graphique : un délai court ferait échouer
              // une requête qui aurait fini par réussir.
              receiveTimeout: const Duration(minutes: 3),
              sendTimeout: const Duration(minutes: 3),
            ),
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final scope = options.extra[authScopeKey];
          final kind = switch (scope) {
            AuthScope.device => TokenKind.device,
            AuthScope.staff => TokenKind.staff,
            _ => null,
          };
          if (kind != null) {
            final token = await _tokenStorage.readToken(kind);
            if (token != null) options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // Session agent expirée : on oublie le jeton et l'espace agent
          // redemande la connexion. Exception : /auth/login renvoie aussi 401
          // pour de simples identifiants erronés.
          final scope = error.requestOptions.extra[authScopeKey];
          if (error.response?.statusCode == 401 &&
              scope == AuthScope.staff &&
              error.requestOptions.path != '/auth/login') {
            await _tokenStorage.clearToken(TokenKind.staff);
            onStaffUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStorage _tokenStorage;

  /// Appelé quand le serveur rejette le jeton d'un agent.
  final void Function()? onStaffUnauthorized;

  /// URL absolue d'un média servi par l'API (`/media/...`).
  static String mediaUrl(String path) => path.startsWith('http') ? path : '$apiBaseUrl$path';

  /// Vrai quand l'échec vient du réseau (pas de connexion, serveur éteint),
  /// et non d'une réponse du serveur : c'est le signal pour basculer sur les
  /// données hors connexion.
  static bool isNetworkError(Object error) => error is ApiException && error.statusCode == null;

  /// Convertit une `DioException` en `ApiException` avec un message lisible.
  /// Centralisé ici (plutôt que répété dans chaque repository) : toutes les
  /// erreurs API prennent la même forme dans toute l'application.
  static Object toApiException(DioException error) {
    if (error.type == DioExceptionType.cancel) return const RequestCancelledException();

    final response = error.response;
    if (response != null) {
      final message = _detailFrom(response.data) ?? 'Erreur du serveur (${response.statusCode}).';
      return ApiException(message, statusCode: response.statusCode);
    }

    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout =>
        ApiException('Le serveur met trop de temps à répondre. Réessayez dans un instant.'),
      DioExceptionType.connectionError => ApiException(
        'Pas de connexion au serveur. Réessayez quand vous aurez internet.',
      ),
      _ => ApiException("Une erreur inattendue s'est produite."),
    };
  }

  /// Extrait le champ `detail` d'une réponse d'erreur FastAPI.
  ///
  /// Le corps arrive parfois déjà décodé en `Map` (requêtes JSON ordinaires),
  /// parfois en octets bruts : les endpoints média sont appelés avec
  /// `responseType: bytes` pour recevoir l'audio/la vidéo, et Dio applique ce
  /// même type à la réponse d'ERREUR. Sans ce décodage, tous les messages
  /// utiles de ces endpoints ("Langue non supportée", "Fichier trop
  /// volumineux", "Le service de clonage vocal n'est pas démarré") étaient
  /// remplacés par un « Erreur du serveur (400) » qui n'aide personne — et
  /// c'est justement là que l'utilisateur a le plus besoin de savoir quoi
  /// corriger.
  static String? _detailFrom(dynamic data) {
    if (data is Map) return _detailFromMap(data);
    if (data is List<int>) {
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map) return _detailFromMap(decoded);
      } catch (_) {
        // Corps non-JSON (page d'erreur HTML d'un proxy, réponse tronquée) :
        // on retombe sur le message générique de l'appelant.
      }
    }
    return null;
  }

  /// `detail` prend deux formes chez FastAPI : une simple chaîne pour les
  /// erreurs qu'on lève nous-mêmes (`HTTPException`), ou une LISTE d'erreurs
  /// de validation (code 422) produite automatiquement par Pydantic quand un
  /// champ est mal formé. Sans ce second cas, un mot de passe trop court ou un
  /// email invalide s'affichait « Erreur du serveur (422) » : techniquement
  /// exact, mais l'utilisateur ne pouvait pas deviner quoi corriger.
  static String? _detailFromMap(Map<dynamic, dynamic> data) {
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        // `loc` vaut typiquement ["body", "password"] : le dernier élément
        // nomme le champ fautif, la seule partie utile pour l'utilisateur.
        final location = first['loc'];
        final field = (location is List && location.isNotEmpty) ? location.last.toString() : null;
        final message = first['msg'] as String;
        return field == null ? message : '$field : $message';
      }
    }
    return null;
  }
}
