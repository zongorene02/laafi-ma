import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/cache.dart';
import '../../../core/storage/json_store.dart';

class CapsuleText {
  const CapsuleText({required this.title, required this.text, this.audioUrl, this.audioKind});

  factory CapsuleText.fromJson(Map<String, dynamic> json) => CapsuleText(
    title: json['title'] as String? ?? '',
    text: json['text'] as String? ?? '',
    audioUrl: json['audio_url'] as String?,
    audioKind: json['audio_kind'] as String?,
  );

  final String title;
  final String text;
  final String? audioUrl;
  final String? audioKind;

  bool get isSynthetic => audioKind == 'synthetic';

  /// L'API renvoie toutes les langues, vides quand le texte manque.
  bool get hasText => title.trim().isNotEmpty && text.trim().isNotEmpty;
}

class QuizItem {
  const QuizItem({required this.question, required this.choices, required this.correctIndex});

  factory QuizItem.fromJson(Map<String, dynamic> json) => QuizItem(
    question: _stringMap(json['question']),
    choices: [for (final c in (json['choices'] as List? ?? const [])) _stringMap(c)],
    correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
  );

  final Map<String, String> question;
  final List<Map<String, String>> choices;
  final int correctIndex;

  String questionIn(String lang) => question[lang] ?? question['fr'] ?? '';
  String choiceIn(int index, String lang) => choices[index][lang] ?? choices[index]['fr'] ?? '';
}

Map<String, String> _stringMap(Object? value) =>
    value is Map ? {for (final e in value.entries) e.key.toString(): e.value?.toString() ?? ''} : const {};

/// `Capsule` de docs/API.md (module 5).
class Capsule {
  const Capsule({
    required this.id,
    required this.track,
    required this.order,
    required this.translations,
    this.quiz = const [],
    this.license,
    this.provisional = false,
    required this.raw,
  });

  factory Capsule.fromJson(Map<String, dynamic> json) => Capsule(
    id: json['id'] as String,
    track: json['track'] as String? ?? 'general',
    order: (json['order'] as num?)?.toInt() ?? 0,
    translations: {
      for (final e in ((json['translations'] as Map?) ?? const {}).entries)
        if (e.value is Map) e.key.toString(): CapsuleText.fromJson((e.value as Map).cast<String, dynamic>()),
    },
    quiz: [for (final q in (json['quiz'] as List? ?? const [])) QuizItem.fromJson((q as Map).cast<String, dynamic>())],
    license: json['license'] as String?,
    provisional: json['provisional'] == true,
    raw: json,
  );

  final String id;
  final String track;
  final int order;
  final Map<String, CapsuleText> translations;
  final List<QuizItem> quiz;
  final String? license;

  /// Contenu tiré d'une source publique, relu par aucune sage-femme.
  final bool provisional;
  final Map<String, dynamic> raw;

  /// Texte dans la langue demandée, en français sinon.
  CapsuleText textIn(String lang) {
    final asked = translations[lang];
    if (asked != null && asked.hasText) return asked;
    return translations['fr'] ?? asked ?? const CapsuleText(title: '', text: '');
  }

  /// Langue réellement affichée (pour la voix et l'étiquette).
  String langShown(String lang) => translations[lang]?.hasText == true ? lang : 'fr';
}

class LearnRepository {
  LearnRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonStore _cache;

  static const collection = 'capsules';

  static String audioBlobKey(String url) => 'media:$url';

  Future<List<Capsule>> fetch(String lang) async {
    try {
      final response = await _dio.get('/learn/capsules', queryParameters: {'lang': lang});
      final raw = [for (final item in response.data as List) (item as Map).cast<String, dynamic>()];
      await writeCache(_cache, collection, lang, raw);
      return _sorted(raw.map(Capsule.fromJson).toList());
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<(List<Capsule>, DateTime)?> cached(String lang) async {
    final entry = await readCache(_cache, collection, lang);
    final data = entry?.data;
    if (data is! List) return null;
    return (
      _sorted([for (final item in data) Capsule.fromJson((item as Map).cast<String, dynamic>())]),
      entry!.fetchedAt,
    );
  }

  Future<(List<Capsule>, bool fromCache)> load(String lang) async {
    try {
      return (await fetch(lang), false);
    } catch (e) {
      final cached = await this.cached(lang);
      if (cached != null) return (cached.$1, true);
      rethrow;
    }
  }

  /// Téléchargement pour hors connexion : le JSON toujours ; les fichiers
  /// audio seulement sur Android (sur le web, le stockage du navigateur est
  /// trop limité pour des fichiers audio).
  Future<int> downloadForOffline(String lang) async {
    final capsules = await fetch(lang);
    if (kIsWeb) return 0;
    var count = 0;
    for (final capsule in capsules) {
      final url = capsule.textIn(lang).audioUrl;
      if (url == null || await _cache.getBlob(audioBlobKey(url)) != null) continue;
      try {
        final response = await _dio.get<List<int>>(
          ApiClient.mediaUrl(url),
          options: Options(responseType: ResponseType.bytes),
        );
        await _cache.putBlob(audioBlobKey(url), Uint8List.fromList(response.data!));
        count++;
      } on DioException {
        // Un fichier manquant n'empêche pas de télécharger les autres.
      }
    }
    return count;
  }

  Future<Uint8List?> cachedAudio(String url) => _cache.getBlob(audioBlobKey(url));

  List<Capsule> _sorted(List<Capsule> list) => list..sort((a, b) => a.order.compareTo(b.order));
}

final learnRepositoryProvider = Provider<LearnRepository>(
  (ref) => LearnRepository(ref.watch(dioProvider), ref.watch(cacheStoreProvider)),
);

/// Capsules de la langue choisie (réseau d'abord, cache en secours).
final capsulesProvider = FutureProvider<(List<Capsule>, bool)>((ref) {
  return ref.watch(learnRepositoryProvider).load(ref.watch(langProvider));
});
