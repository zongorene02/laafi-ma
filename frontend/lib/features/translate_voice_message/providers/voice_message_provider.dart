import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../core/constants/languages.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/translation_engine.dart';
import '../../../shared/data/audio_playback_service.dart';
import '../../../shared/data/wav_utils.dart';

enum VoiceMessageStatus { idle, recording, translating, done, error }

class VoiceMessageState {
  const VoiceMessageState({
    this.status = VoiceMessageStatus.idle,
    this.sourceLang = 'fr',
    this.targetLang = 'en',
    this.preserveVoice = false,
    this.sourceText,
    this.translatedText,
    this.audioBytes,
    this.errorMessage,
    this.uploadProgress,
    this.resultEngine = TranslationEngine.verified,
  });

  final VoiceMessageStatus status;
  final String sourceLang;
  final String targetLang;
  final bool preserveVoice;
  final String? sourceText;
  final String? translatedText;
  final Uint8List? audioBytes;
  final String? errorMessage;

  /// Fraction de l'audio deja envoyee (0 a 1), `null` pendant que le serveur
  /// travaille — voir `LongOperationIndicator`.
  final double? uploadProgress;

  /// Moteur qui a produit le résultat affiché (voir `EngineBadge`).
  final TranslationEngine resultEngine;

  bool get canPreserveVoice => kVoiceCloneLanguageCodes.contains(targetLang);

  VoiceMessageState copyWith({
    VoiceMessageStatus? status,
    String? sourceLang,
    String? targetLang,
    bool? preserveVoice,
    String? sourceText,
    String? translatedText,
    Uint8List? audioBytes,
    String? errorMessage,
    double? uploadProgress,
    TranslationEngine? resultEngine,
    bool clearUploadProgress = false,
    bool clearResult = false,
  }) => VoiceMessageState(
    status: status ?? this.status,
    sourceLang: sourceLang ?? this.sourceLang,
    targetLang: targetLang ?? this.targetLang,
    preserveVoice: preserveVoice ?? this.preserveVoice,
    sourceText: clearResult ? null : (sourceText ?? this.sourceText),
    translatedText: clearResult ? null : (translatedText ?? this.translatedText),
    audioBytes: clearResult ? null : (audioBytes ?? this.audioBytes),
    errorMessage: clearResult ? null : errorMessage,
    uploadProgress: clearUploadProgress ? null : (uploadProgress ?? this.uploadProgress),
    resultEngine: resultEngine ?? this.resultEngine,
  );
}

/// Enregistre UN message (contrairement à la conversation en direct, voir
/// `translate_voice`), l'encapsule en .wav (voir `wav_utils.dart`), puis
/// appelle le pipeline synchrone `/translate-voice` — seul endpoint qui
/// supporte `preserve_voice` (clonage vocal), non disponible sur le canal
/// temps réel (voir `backend/services/core-service/app/main.py`,
/// `ws_translate_voice`, qui ne l'implémente pas).
class VoiceMessageController extends AutoDisposeNotifier<VoiceMessageState> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  BytesBuilder? _buffer;
  CancelToken? _cancelToken;

  @override
  VoiceMessageState build() {
    // `stop()` avant `dispose()` : quitter l'ecran pendant un enregistrement
    // doit VRAIMENT eteindre le micro, pas seulement liberer l'objet Dart.
    ref.onDispose(() {
      _subscription?.cancel();
      _recorder.stop();
      _recorder.dispose();
      _cancelToken?.cancel();
    });
    return const VoiceMessageState(sourceLang: 'fr', targetLang: 'mos');
  }

  void setSourceLang(String lang) => state = state.copyWith(sourceLang: lang, clearResult: true);

  void setTargetLang(String lang) {
    final canStillPreserve = kVoiceCloneLanguageCodes.contains(lang);
    state = state.copyWith(
      targetLang: lang,
      preserveVoice: canStillPreserve ? state.preserveVoice : false,
      clearResult: true,
    );
  }

  void setPreserveVoice(bool value) => state = state.copyWith(preserveVoice: value);

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(
        status: VoiceMessageStatus.error,
        errorMessage: "Micro refusé. Autorisez l'accès au micro dans les réglages de votre appareil.",
      );
      return;
    }
    // `startStream` peut echouer pour des raisons tout a fait ordinaires : le
    // micro deja pris par une autre application, un peripherique debranche en
    // cours de route, un navigateur qui exige HTTPS. Sans ce try/catch,
    // l'exception se perdait dans le vide et l'ecran restait bloque sur
    // "pret a enregistrer" — un bouton qui ne fait rien, sans le moindre
    // message.
    try {
      _buffer = BytesBuilder();
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      _subscription = stream.listen((chunk) => _buffer!.add(chunk));
      state = state.copyWith(status: VoiceMessageStatus.recording, clearResult: true);
    } catch (e) {
      _buffer = null;
      state = state.copyWith(
        status: VoiceMessageStatus.error,
        errorMessage: "Impossible de demarrer l'enregistrement (micro occupe par une autre application ?)",
      );
    }
  }

  /// Traduit un fichier audio EXISTANT (choisi via un sélecteur de fichiers,
  /// voir l'écran) plutôt qu'un enregistrement live — le backend accepte
  /// n'importe quel format audio courant (mp3, m4a, wav...) et le décode via
  /// ffmpeg (voir `any_audio_or_video_to_wav_array` côté core-service), donc
  /// aucun besoin de l'encapsuler en .wav nous-mêmes comme pour le PCM brut
  /// du micro (voir `stopAndTranslate` ci-dessous).
  Future<void> translateAudioFile({required Uint8List fileBytes, required String filename}) async {
    state = state.copyWith(status: VoiceMessageStatus.translating, clearResult: true, uploadProgress: 0);
    await _translate(audioBytes: fileBytes, filename: filename);
  }

  Future<void> stopAndTranslate() async {
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;

    final pcmBytes = _buffer?.toBytes();
    _buffer = null;
    if (pcmBytes == null || pcmBytes.isEmpty) {
      state = state.copyWith(status: VoiceMessageStatus.idle);
      return;
    }

    state = state.copyWith(status: VoiceMessageStatus.translating, uploadProgress: 0);
    await _translate(audioBytes: wrapPcm16AsWav(pcmBytes), filename: 'message.wav');
  }

  /// Corps commun aux deux points d'entree (micro et fichier choisi) : meme
  /// appel reseau, meme gestion de la progression, de l'annulation et des
  /// erreurs. Ecrit une fois plutot que deux, pour qu'une correction faite ici
  /// profite aux deux chemins — ils avaient deja divergé une fois.
  Future<void> _translate({required Uint8List audioBytes, required String filename}) async {
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final engine = effectiveEngine(ref);
    try {
      final result = await ref
          .read(translationApiProvider)
          .translateVoice(
            audioBytes: audioBytes,
            sourceLang: state.sourceLang,
            targetLang: state.targetLang,
            filename: filename,
            preserveVoice: state.preserveVoice,
            engine: engine,
            cancelToken: cancelToken,
            onSendProgress: (sent, total) {
              if (total <= 0) return;
              final progress = sent / total;
              // A 100 %, l'audio est parti mais le serveur commence seulement
              // a transcrire, traduire puis resynthetiser : on bascule sur une
              // attente indeterminee au lieu de laisser une barre pleine qui
              // laisserait croire que c'est termine.
              state = progress >= 1
                  ? state.copyWith(clearUploadProgress: true)
                  : state.copyWith(uploadProgress: progress);
            },
          );
      state = state.copyWith(
        status: VoiceMessageStatus.done,
        resultEngine: engine,
        sourceText: result.sourceText,
        translatedText: result.translatedText,
        audioBytes: result.mediaBytes,
        clearUploadProgress: true,
      );
      await ref.read(audioPlaybackServiceProvider).play(result.mediaBytes);
    } on RequestCancelledException {
      // Annulation volontaire : retour a l'etat initial, sans bandeau rouge.
      state = state.copyWith(status: VoiceMessageStatus.idle, clearUploadProgress: true);
    } catch (e) {
      state = state.copyWith(status: VoiceMessageStatus.error, errorMessage: e.toString(), clearUploadProgress: true);
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() => _cancelToken?.cancel();

  void replay() {
    if (state.audioBytes != null) {
      ref.read(audioPlaybackServiceProvider).play(state.audioBytes!);
    }
  }

  void reset() => state = VoiceMessageState(sourceLang: state.sourceLang, targetLang: state.targetLang);
}

// `autoDispose` : quitter l'ecran libere le micro et efface le message
// precedent (voir translate_text_provider.dart pour le meme raisonnement).
final voiceMessageControllerProvider = AutoDisposeNotifierProvider<VoiceMessageController, VoiceMessageState>(
  VoiceMessageController.new,
);
