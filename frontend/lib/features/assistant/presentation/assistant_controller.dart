import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/security/secret_phrase.dart';
import '../../../core/security/session.dart';
import '../../../shared/data/audio_playback_service.dart';
import '../../../shared/data/wav_utils.dart';
import '../../stats/stats_service.dart';
import '../data/assistant_models.dart';
import '../data/assistant_repository.dart';
import '../data/danger_detector.dart';

/// [confirming] : la question reconnue à la voix attend le « Oui » de la femme.
enum AssistantStatus { idle, recording, sending, confirming, done, offline, error }

class AssistantState {
  const AssistantState({
    this.status = AssistantStatus.idle,
    this.answer,
    this.question,
    this.offlineDanger = const [],
    this.offlineFaq = const [],
    this.error,
    this.transcript,
    this.voice = false,
    this.understood,
    this.openHelp = false,
  });

  final AssistantStatus status;
  final AssistantAnswer? answer;

  /// Question tapée, ou question vocale confirmée.
  final String? question;
  final List<DangerSign> offlineDanger;
  final List<FaqEntry> offlineFaq;
  final String? error;

  /// Ce que le serveur a compris, à faire confirmer ([AssistantStatus.confirming]).
  final String? transcript;

  /// La question a été posée avec le micro.
  final bool voice;

  /// Réponse à « Avez-vous compris ? » (`null` = pas encore répondu).
  final bool? understood;

  /// Phrase d'aide secrète reconnue : l'écran ouvre la page Aide. Rien
  /// d'autre ne change à l'écran (aucun message ne le trahit).
  final bool openHelp;

  AssistantState withUnderstood(bool value) => AssistantState(
    status: status,
    answer: answer,
    question: question,
    offlineDanger: offlineDanger,
    offlineFaq: offlineFaq,
    error: error,
    transcript: transcript,
    voice: voice,
    understood: value,
  );
}

/// Pilote l'assistant :
/// - micro → `transcribe` → « Vous avez demandé : … ? » → `ask-text` (repli
///   sur `ask-voice` si le serveur ne connaît pas `transcribe`) ;
/// - texte → `ask-text` ;
/// - repli hors connexion (signes de danger + FAQ en cache).
///
/// Avant tout envoi, la question est comparée SUR LE TÉLÉPHONE à la phrase
/// d'aide secrète du profil : si c'est elle, rien ne part au serveur et la
/// page Aide s'ouvre.
class AssistantController extends AutoDisposeNotifier<AssistantState> {
  /// Créé au premier enregistrement seulement (pas de micro pour une
  /// question tapée).
  AudioRecorder? _recorderInstance;
  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  BytesBuilder? _buffer;
  Timer? _maxDuration;

  /// 60 s de PCM 16 kHz mono ≈ 1,9 Mo : bien sous la limite de 10 Mo.
  static const maxRecording = Duration(seconds: 60);
  static const _filename = 'question.wav';

  @override
  AssistantState build() {
    ref.onDispose(() {
      _maxDuration?.cancel();
      _subscription?.cancel();
      final recorder = _recorderInstance;
      if (recorder != null) {
        recorder.stop();
        recorder.dispose();
      }
    });
    return const AssistantState();
  }

  String get _lang => ref.read(langProvider);

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      state = const AssistantState(status: AssistantStatus.error, error: S.micDenied);
      return;
    }
    try {
      await ref.read(audioPlaybackServiceProvider).stop();
      _buffer = BytesBuilder();
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      _subscription = stream.listen((chunk) => _buffer?.add(chunk));
      _maxDuration = Timer(maxRecording, stopAndSend);
      state = const AssistantState(status: AssistantStatus.recording);
    } catch (_) {
      _buffer = null;
      state = const AssistantState(status: AssistantStatus.error, error: S.micDenied);
    }
  }

  Future<void> stopAndSend() async {
    if (state.status != AssistantStatus.recording) return;
    _maxDuration?.cancel();
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    final pcm = _buffer?.toBytes();
    _buffer = null;
    if (pcm == null || pcm.isEmpty) {
      state = const AssistantState();
      return;
    }
    await sendVoice(wrapPcm16AsWav(pcm));
  }

  /// Envoie un enregistrement WAV (séparé de [stopAndSend] pour les tests).
  Future<void> sendVoice(Uint8List wav) async {
    state = const AssistantState(status: AssistantStatus.sending, voice: true);
    final repo = ref.read(assistantRepositoryProvider);
    try {
      final transcription = await repo.transcribe(wav, _filename, _lang);
      if (transcription == null) {
        // Serveur plus ancien, sans `transcribe` : question posée directement.
        final answer = await repo.askVoice(wav, _filename, _lang);
        if (await _isHelpPhrase([answer.transcript, answer.questionFr])) {
          _openHelp();
          return;
        }
        await _onAnswer(answer, voice: true);
        return;
      }
      if (await _isHelpPhrase([transcription.transcript, transcription.questionFr])) {
        _openHelp();
        return;
      }
      final text = transcription.transcript.trim();
      state = text.isEmpty
          ? const AssistantState(status: AssistantStatus.error, error: S.notHeard)
          : AssistantState(status: AssistantStatus.confirming, transcript: text, voice: true);
    } on ApiException catch (e) {
      state = AssistantState(
        status: AssistantStatus.error,
        error: e.statusCode == 503
            ? S.voiceUnavailable
            : (ApiClient.isNetworkError(e) ? '${e.message} ${S.voiceUnavailable}' : e.message),
      );
    }
  }

  /// « Oui » : la question reconnue part par `ask-text`, dans la même langue.
  Future<void> confirmTranscript() async {
    final text = state.transcript;
    if (state.status != AssistantStatus.confirming || text == null) return;
    await _ask(text, voice: true);
  }

  /// « Non, je répète » : retour au micro.
  void rejectTranscript() => reset();

  Future<void> askText(String text) => _ask(text, voice: false);

  Future<void> _ask(String text, {required bool voice}) async {
    final question = text.trim();
    if (question.isEmpty) return;
    if (await _isHelpPhrase([question])) {
      _openHelp();
      return;
    }
    state = AssistantState(status: AssistantStatus.sending, question: question, voice: voice);
    try {
      final answer = await ref.read(assistantRepositoryProvider).askText(question, _lang);
      await _onAnswer(answer, voice: voice);
    } on ApiException catch (e) {
      if (!ApiClient.isNetworkError(e)) {
        state = AssistantState(status: AssistantStatus.error, error: e.message, question: question, voice: voice);
        return;
      }
      await _offline(question, voice: voice);
    }
  }

  /// La phrase d'aide n'existe que pour un profil réel ; le profil leurre
  /// n'en a pas.
  Future<bool> _isHelpPhrase(List<String?> texts) async {
    final session = ref.read(sessionProvider);
    if (!session.unlocked || session.isDecoy) return false;
    try {
      final phrase = await ref.read(secretPhraseStoreProvider).read(session.profileIndex);
      return texts.any((text) => text != null && matchesSecretPhrase(text, phrase));
    } catch (_) {
      return false;
    }
  }

  void _openHelp() => state = const AssistantState(openHelp: true);

  Future<void> _offline(String question, {required bool voice}) async {
    final repo = ref.read(assistantRepositoryProvider);
    final signs = await repo.offlineDangerSigns(_lang);
    final danger = detectDangerSigns(question, signs);
    final faq = (await repo.cachedFaq(_lang))?.$1.entries ?? const <FaqEntry>[];
    final stats = ref.read(statsServiceProvider);
    await stats.track(StatEvent.questionAsked);
    if (voice) await stats.track(StatEvent.questionVoice);
    if (danger.isNotEmpty) await stats.track(StatEvent.dangerFlagged);
    state = AssistantState(
      status: AssistantStatus.offline,
      question: question,
      voice: voice,
      offlineDanger: danger,
      offlineFaq: closestFaqEntries(question, faq),
    );
  }

  Future<void> _onAnswer(AssistantAnswer answer, {required bool voice}) async {
    state = AssistantState(status: AssistantStatus.done, answer: answer, question: state.question, voice: voice);
    final stats = ref.read(statsServiceProvider);
    await stats.track(StatEvent.questionAsked);
    if (voice) await stats.track(StatEvent.questionVoice);
    if (!answer.matched) await stats.track(StatEvent.questionUnanswered);
    if (answer.danger) await stats.track(StatEvent.dangerFlagged);
    await replayAnswer();
  }

  /// Rejoue l'audio de la réponse (s'il existe).
  Future<void> replayAnswer() async {
    final url = state.answer?.entry?.audioUrl;
    if (url == null) return;
    try {
      await ref.read(audioPlaybackServiceProvider).playUrl(ApiClient.mediaUrl(url));
    } catch (_) {
      // La réponse reste lisible et réécoutable avec le bouton.
    }
  }

  /// « Avez-vous compris ? » : une seule réponse comptée par réponse affichée.
  Future<void> markUnderstood(bool understood) async {
    if (state.status != AssistantStatus.done || state.answer?.entry == null || state.understood != null) return;
    state = state.withUnderstood(understood);
    await ref.read(statsServiceProvider).track(understood ? StatEvent.answerUnderstood : StatEvent.answerNotUnderstood);
  }

  void reset() => state = const AssistantState();
}

final assistantControllerProvider = AutoDisposeNotifierProvider<AssistantController, AssistantState>(
  AssistantController.new,
);
