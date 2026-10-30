import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/json_store.dart';
import '../../core/translation_engine.dart';
import 'audio_playback_service.dart';
import 'translation_api.dart';

/// Lecture à voix haute des textes de l'interface (bouton « Écouter »).
///
/// - Langue française : la voix du TÉLÉPHONE d'abord (gratuite, hors
///   connexion), le serveur en secours.
/// - Mooré / Dioula : le texte français de l'écran est traduit puis
///   synthétisé par le serveur (`POST /translate` + `POST /text-to-speech`).
///   L'audio obtenu est gardé dans le cache chiffré : la deuxième écoute
///   marche sans internet.
/// - [speakPrivate] lit les notes personnelles de la femme (recommandations
///   d'une consultation…) UNIQUEMENT avec la voix du téléphone : ces textes ne
///   partent jamais vers le serveur.
class ListenService {
  ListenService({required this._api, required this._cache, required this._player, required this._lang, this._tts});

  final TranslationApi _api;
  final JsonStore _cache;
  final AudioPlaybackService _player;
  final String Function() _lang;
  FlutterTts? _tts;

  static String cacheKey(String lang, String text) => 'tts_${lang}_${fnv1a(text)}';

  Future<void> speak(String frenchText) async {
    final lang = _lang();
    await stop();
    if (lang == 'fr' && await _speakOnDevice(frenchText)) return;

    final key = cacheKey(lang, frenchText);
    Uint8List? audio = await _cache.getBlob(key);
    if (audio == null) {
      try {
        var text = frenchText;
        if (lang != 'fr') {
          text = await _api.translateText(
            text: frenchText,
            sourceLang: 'fr',
            targetLang: lang,
            engine: TranslationEngine.verified,
            scope: AuthScope.none,
          );
        }
        audio = await _api.textToSpeech(text: text, language: lang, scope: AuthScope.none);
        await _cache.putBlob(key, audio);
      } catch (_) {
        // Pas de réseau ni de cache : la voix française du téléphone vaut
        // mieux que le silence.
        if (await _speakOnDevice(frenchText)) return;
        rethrow;
      }
    }
    await _player.play(audio);
  }

  /// Contenu DÉJÀ dans la bonne langue (réponse validée sans audio…).
  Future<void> speakContent(String text, String lang) async {
    await stop();
    if (lang == 'fr' && await _speakOnDevice(text)) return;
    final key = cacheKey(lang, text);
    var audio = await _cache.getBlob(key);
    if (audio == null) {
      audio = await _api.textToSpeech(text: text, language: lang, scope: AuthScope.none);
      await _cache.putBlob(key, audio);
    }
    await _player.play(audio);
  }

  Future<bool> speakPrivate(String text) async {
    await stop();
    return _speakOnDevice(text);
  }

  Future<void> stop() async {
    await _player.stop();
    try {
      await _tts?.stop();
    } catch (_) {
      // Synthèse du téléphone absente : rien à arrêter.
    }
  }

  Future<bool> _speakOnDevice(String text) async {
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage('fr-FR');
      await tts.setSpeechRate(0.45);
      final result = await tts.speak(text);
      return result == 1 || result == true;
    } catch (_) {
      return false;
    }
  }
}

/// Empreinte FNV-1a 32 bits : clé de cache courte et stable d'un texte.
String fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    // Multiplication par le nombre premier FNV (2^24 + 0x193) décomposée :
    // un produit direct dépasserait 2^53 et perdrait des bits sur le web.
    hash = (hash * 0x193 + ((hash << 24) & 0xffffffff)) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Entier stable dérivé d'un identifiant texte (identifiants de rappels).
int stableIntId(String text) => int.parse(fnv1a(text), radix: 16) & 0x7fffffff;

final listenServiceProvider = Provider<ListenService>(
  (ref) => ListenService(
    api: ref.watch(translationApiProvider),
    cache: ref.watch(cacheStoreProvider),
    player: ref.watch(audioPlaybackServiceProvider),
    lang: () => ref.read(langProvider),
  ),
);
