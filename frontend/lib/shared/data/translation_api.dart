import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/translation_engine.dart';

/// Endpoints de traduction repris de Trad IA (`/translate`, `/text-to-speech`,
/// `/speech-to-text`, `/translate-voice`). Par défaut, les appels portent le
/// jeton agent.
///
/// Le bouton « Écouter » de l'application des femmes appelle `/translate` et
/// `/text-to-speech` SANS jeton (`AuthScope.none`) : ces deux endpoints sont
/// publics d'après docs/API.md, les deux autres restent réservés aux agents.
class TranslationApi {
  TranslationApi(this._dio);

  final Dio _dio;

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
    TranslationEngine engine = TranslationEngine.verified,
    CancelToken? cancelToken,
    AuthScope scope = AuthScope.staff,
  }) async {
    try {
      final response = await _dio.post(
        '/translate',
        data: {'text': text, 'source_lang': sourceLang, 'target_lang': targetLang, 'mode': engine.apiValue},
        cancelToken: cancelToken,
        options: scoped(scope),
      );
      return response.data['translation'] as String;
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<bool> fastModeAvailable() async {
    try {
      final response = await _dio.get('/health');
      return response.data['fast_mode_available'] == true;
    } on DioException {
      return false;
    }
  }

  /// Renvoie l'audio .wav synthétisé, brut.
  Future<Uint8List> textToSpeech({
    required String text,
    required String language,
    AuthScope scope = AuthScope.staff,
  }) async {
    try {
      final response = await _dio.post(
        '/text-to-speech',
        data: {'text': text, 'language': language},
        options: scoped(scope, base: Options(responseType: ResponseType.bytes)),
      );
      return Uint8List.fromList(response.data as List<int>);
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<String> speechToText({
    required Uint8List audioBytes,
    required String language,
    required String filename,
  }) async {
    try {
      final formData = FormData.fromMap({
        'language': language,
        'audio': MultipartFile.fromBytes(audioBytes, filename: filename),
      });
      final response = await _dio.post('/speech-to-text', data: formData, options: scoped(AuthScope.staff));
      return response.data['text'] as String;
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  /// Pipeline voix -> voix. Les textes intermédiaires arrivent dans les
  /// en-têtes `X-Source-Text` / `X-Translated-Text` (encodés en URI).
  Future<MediaTranslationResult> translateVoice({
    required Uint8List audioBytes,
    required String sourceLang,
    required String targetLang,
    required String filename,
    bool preserveVoice = false,
    TranslationEngine engine = TranslationEngine.verified,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'source_lang': sourceLang,
        'target_lang': targetLang,
        'preserve_voice': preserveVoice,
        'mode': engine.apiValue,
        'audio': MultipartFile.fromBytes(audioBytes, filename: filename),
      });
      final response = await _dio.post(
        '/translate-voice',
        data: formData,
        options: scoped(AuthScope.staff, base: Options(responseType: ResponseType.bytes)),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );
      final headers = response.headers;
      return MediaTranslationResult(
        mediaBytes: Uint8List.fromList(response.data as List<int>),
        sourceText: Uri.decodeComponent(headers.value('x-source-text') ?? ''),
        translatedText: Uri.decodeComponent(headers.value('x-translated-text') ?? ''),
      );
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }
}

class MediaTranslationResult {
  const MediaTranslationResult({required this.mediaBytes, required this.sourceText, required this.translatedText});

  final Uint8List mediaBytes;
  final String sourceText;
  final String translatedText;
}
