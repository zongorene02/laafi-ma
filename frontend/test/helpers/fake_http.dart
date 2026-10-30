import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:laafi_ma/core/network/api_client.dart';
import 'package:laafi_ma/core/storage/secret_store.dart';
import 'package:laafi_ma/core/storage/token_storage.dart';

typedef FakeHandler = FutureOr<ResponseBody> Function(RequestOptions request);

/// Adaptateur HTTP factice : aucune requête ne sort de la machine de test,
/// chaque requête est enregistrée pour vérifier chemin, en-têtes et corps.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FakeHandler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object? data, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody emptyResponse(int status) => ResponseBody.fromString('', status);

/// Client complet (intercepteur de jetons compris) branché sur [FakeAdapter].
({ApiClient client, FakeAdapter adapter, TokenStorage tokens}) fakeApi(FakeHandler handler) {
  final adapter = FakeAdapter(handler);
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = adapter;
  final tokens = TokenStorage(MemorySecretStore());
  return (client: ApiClient(tokens, dio: dio), adapter: adapter, tokens: tokens);
}
