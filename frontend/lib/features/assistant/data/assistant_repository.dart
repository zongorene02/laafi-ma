import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/cache.dart';
import '../../../core/storage/json_store.dart';
import 'assistant_models.dart';

/// Appels du module 1 (aucun jeton requis) et cache hors connexion.
class AssistantRepository {
  AssistantRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonStore _cache;

  static const faqCollection = 'faq';
  static const dangerCollection = 'danger_signs';

  Future<AssistantAnswer> askText(String text, String lang) async {
    try {
      final response = await _dio.post('/assistant/ask-text', data: {'text': text, 'lang': lang});
      return AssistantAnswer.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<AssistantAnswer> askVoice(Uint8List audio, String filename, String lang) async {
    try {
      final form = FormData.fromMap({'audio': MultipartFile.fromBytes(audio, filename: filename), 'lang': lang});
      final response = await _dio.post('/assistant/ask-voice', data: form);
      return AssistantAnswer.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  /// Reconnaissance seule (rien n'est enregistré côté serveur), pour faire
  /// confirmer la question et la comparer à la phrase d'aide sur le
  /// téléphone. `null` si le serveur ne connaît pas encore ce point d'accès
  /// (`404`) : l'appelant revient alors à [askVoice].
  Future<Transcription?> transcribe(Uint8List audio, String filename, String lang) async {
    try {
      final form = FormData.fromMap({'audio': MultipartFile.fromBytes(audio, filename: filename), 'lang': lang});
      final response = await _dio.post('/assistant/transcribe', data: form);
      return Transcription.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiClient.toApiException(e);
    }
  }

  Future<FaqBundle> fetchFaq(String lang) async {
    try {
      final response = await _dio.get('/assistant/faq', queryParameters: {'lang': lang});
      final bundle = FaqBundle.fromJson((response.data as Map).cast<String, dynamic>());
      await writeCache(_cache, faqCollection, lang, bundle.toJson());
      return bundle;
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<List<DangerSign>> fetchDangerSigns(String lang) async {
    try {
      final response = await _dio.get('/assistant/danger-signs', queryParameters: {'lang': lang});
      final signs = [
        for (final item in response.data as List) DangerSign.fromJson((item as Map).cast<String, dynamic>()),
      ];
      await writeCache(_cache, dangerCollection, lang, signs.map((s) => s.toJson()).toList());
      return signs;
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  /// Tout ce qu'il faut pour l'usage hors connexion dans une langue : la FAQ,
  /// les signes de danger dans cette langue (libellés) et en français (les
  /// mots-clés de détection sont en français).
  Future<void> downloadForOffline(String lang) async {
    await fetchFaq(lang);
    await fetchDangerSigns('fr');
    if (lang != 'fr') await fetchDangerSigns(lang);
  }

  Future<(FaqBundle, DateTime)?> cachedFaq(String lang) async {
    final entry = await readCache(_cache, faqCollection, lang);
    if (entry?.data is! Map) return null;
    return (FaqBundle.fromJson((entry!.data as Map).cast<String, dynamic>()), entry.fetchedAt);
  }

  Future<List<DangerSign>> cachedDangerSigns(String lang) async {
    final entry = await readCache(_cache, dangerCollection, lang);
    final data = entry?.data;
    if (data is! List) return const [];
    return [for (final item in data) DangerSign.fromJson((item as Map).cast<String, dynamic>())];
  }

  /// Signes en cache avec mots-clés français, libellés et conseils dans la
  /// langue choisie quand ils sont disponibles.
  Future<List<DangerSign>> offlineDangerSigns(String lang) async {
    final french = await cachedDangerSigns('fr');
    if (lang == 'fr') return french;
    final localized = {for (final s in await cachedDangerSigns(lang)) s.id: s};
    return [
      for (final sign in french)
        DangerSign(
          id: sign.id,
          label: localized[sign.id]?.label ?? sign.label,
          advice: localized[sign.id]?.advice ?? sign.advice,
          keywords: sign.keywords,
          agentQuestions: localized[sign.id]?.agentQuestions ?? sign.agentQuestions,
          referWhen: localized[sign.id]?.referWhen ?? sign.referWhen,
          // Dans le doute (caches d'âges différents), le signe reste signalé.
          provisional: sign.provisional || (localized[sign.id]?.provisional ?? false),
          source: localized[sign.id]?.source ?? sign.source,
        ),
    ];
  }
}

final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => AssistantRepository(ref.watch(dioProvider), ref.watch(cacheStoreProvider)),
);
