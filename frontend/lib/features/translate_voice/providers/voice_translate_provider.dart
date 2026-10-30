import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../core/providers.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/translation_engine.dart';
import '../../../shared/data/audio_playback_service.dart';
import '../data/realtime_translate_socket.dart';

enum ConversationStatus { idle, connecting, listening, error }

class ConversationTurn {
  const ConversationTurn({
    required this.sourceText,
    required this.translatedText,
    required this.engine,
    this.audioBytes,
  });

  final String sourceText;
  final String translatedText;

  /// Moteur qui a traduit CE tour : fixé pour toute la conversation à son
  /// ouverture, mais une conversation effacée puis relancée peut changer de
  /// moteur — chaque tour garde donc le sien.
  final TranslationEngine engine;
  final Uint8List? audioBytes;

  ConversationTurn withAudio(Uint8List bytes) =>
      ConversationTurn(sourceText: sourceText, translatedText: translatedText, engine: engine, audioBytes: bytes);
}

class VoiceConversationState {
  const VoiceConversationState({
    this.status = ConversationStatus.idle,
    this.sourceLang = 'fr',
    this.targetLang = 'en',
    this.turns = const [],
    this.errorMessage,
  });

  final ConversationStatus status;
  final String sourceLang;
  final String targetLang;
  final List<ConversationTurn> turns;
  final String? errorMessage;

  bool get isActive => status == ConversationStatus.listening || status == ConversationStatus.connecting;

  VoiceConversationState copyWith({
    ConversationStatus? status,
    String? sourceLang,
    String? targetLang,
    List<ConversationTurn>? turns,
    String? errorMessage,
  }) => VoiceConversationState(
    status: status ?? this.status,
    sourceLang: sourceLang ?? this.sourceLang,
    targetLang: targetLang ?? this.targetLang,
    turns: turns ?? this.turns,
    errorMessage: errorMessage,
  );
}

/// Pilote toute la conversation temps réel : ouvre le WebSocket, démarre
/// l'enregistrement micro en flux PCM brut, relaie chaque paquet au serveur,
/// et transforme les événements reçus en tours de conversation affichables.
///
/// Découpage volontaire entre le SOCKET (protocole réseau, voir
/// `realtime_translate_socket.dart`) et ce contrôleur (état de
/// l'application) : le contrôleur ne connaît aucun détail JSON/binaire, il
/// réagit à des événements déjà typés.
class VoiceConversationController extends AutoDisposeNotifier<VoiceConversationState> {
  RealtimeTranslateSocket? _socket;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSubscription;
  StreamSubscription<RealtimeTurnEvent>? _eventSubscription;

  /// Moteur choisi à l'ouverture du canal : le serveur le fixe pour toute la
  /// conversation.
  TranslationEngine _engine = TranslationEngine.verified;

  /// Vrai pendant qu'on joue une traduction dans le haut-parleur. Voir
  /// `_sendAudioChunk` : c'est ce qui empêche la boucle d'écho.
  bool _isPlayingBack = false;

  @override
  VoiceConversationState build() {
    // `keepAlive` volontairement ABSENT (provider autoDispose) : quand
    // l'utilisateur quitte l'écran de conversation, ce contrôleur est
    // détruit et le micro s'éteint. Auparavant le provider survivait à
    // l'écran — le micro continuait d'enregistrer et le WebSocket restait
    // ouvert en arrière-plan, indéfiniment, avec l'indicateur
    // d'enregistrement du téléphone allumé sans la moindre explication.
    ref.onDispose(() {
      _pcmSubscription?.cancel();
      _eventSubscription?.cancel();
      _recorder.stop();
      _recorder.dispose();
      _socket?.close();
    });
    return const VoiceConversationState(sourceLang: 'fr', targetLang: 'mos');
  }

  void setSourceLang(String lang) => state = state.copyWith(sourceLang: lang);

  void setTargetLang(String lang) => state = state.copyWith(targetLang: lang);

  Future<void> start() async {
    if (state.isActive) return;

    if (!await _recorder.hasPermission()) {
      state = state.copyWith(status: ConversationStatus.error, errorMessage: 'Permission micro refusée.');
      return;
    }

    state = state.copyWith(status: ConversationStatus.connecting, errorMessage: null);

    try {
      final token = await ref.read(tokenStorageProvider).readToken(TokenKind.staff);
      if (token == null) throw Exception('Session expirée, reconnectez-vous.');

      _engine = effectiveEngine(ref);
      _socket = await RealtimeTranslateSocket.connect(
        token: token,
        sourceLang: state.sourceLang,
        targetLang: state.targetLang,
        engine: _engine,
      );
      _eventSubscription = _socket!.events.listen(_handleEvent);

      final pcmStream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      _pcmSubscription = pcmStream.listen(_sendAudioChunk);

      state = state.copyWith(status: ConversationStatus.listening);
    } catch (e) {
      // On ne laisse jamais un micro ou un socket ouvert derrière une erreur :
      // `startStream` peut échouer APRÈS que le WebSocket soit connecté (micro
      // occupé par une autre application, permission révoquée entre-temps), et
      // sans ce nettoyage la connexion restait ouverte pour rien — et un
      // deuxième essai butait ensuite sur un micro déjà pris.
      await _releaseResources();
      state = state.copyWith(status: ConversationStatus.error, errorMessage: _readableError(e));
    }
  }

  /// N'envoie RIEN pendant qu'une traduction sort du haut-parleur.
  ///
  /// Sans ça, sur un téléphone tenu à la main (haut-parleur et micro à
  /// quelques centimètres), le micro réentend la traduction que l'app vient
  /// de prononcer, l'envoie au serveur, qui la retranscrit et la retraduit —
  /// et ainsi de suite : une boucle d'écho qui remplit la conversation de
  /// tours fantômes et sature le CPU du serveur. Un vrai casque ou l'annulation
  /// d'écho du système évitent le problème, mais on ne peut pas compter dessus.
  void _sendAudioChunk(Uint8List chunk) {
    if (_isPlayingBack) return;
    _socket?.sendAudioChunk(chunk);
  }

  Future<void> _releaseResources() async {
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _recorder.stop();
    await _socket?.close();
    _socket = null;
  }

  Future<void> stop() async {
    await _releaseResources();
    if (state.status != ConversationStatus.error) {
      state = state.copyWith(status: ConversationStatus.idle);
    }
  }

  String _readableError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('SocketException') || message.contains('WebSocketException')) {
      return 'Impossible de joindre le serveur de traduction. Vérifiez votre connexion.';
    }
    return message;
  }

  void _handleEvent(RealtimeTurnEvent event) {
    switch (event) {
      case RealtimeTurnText(:final sourceText, :final translatedText):
        state = state.copyWith(
          turns: [
            ...state.turns,
            ConversationTurn(sourceText: sourceText, translatedText: translatedText, engine: _engine),
          ],
        );
      case RealtimeTurnAudio(:final bytes):
        if (state.turns.isEmpty) return;
        final updatedTurns = [...state.turns];
        updatedTurns[updatedTurns.length - 1] = updatedTurns.last.withAudio(bytes);
        state = state.copyWith(turns: updatedTurns);
        _playWithoutEcho(bytes);
      case RealtimeTurnError(:final message):
        state = state.copyWith(errorMessage: message);
    }
  }

  Future<void> _playWithoutEcho(Uint8List bytes) async {
    _isPlayingBack = true;
    try {
      await ref.read(audioPlaybackServiceProvider).playAndWait(bytes);
    } finally {
      // `finally` : si la lecture échoue (format inattendu, sortie audio
      // débranchée), le micro doit REPRENDRE — sans ça, l'utilisateur se
      // retrouverait avec une conversation qui a l'air active mais qui
      // n'écoute plus rien, sans aucun message d'erreur.
      _isPlayingBack = false;
    }
  }

  void replayTurn(ConversationTurn turn) {
    if (turn.audioBytes != null) {
      _playWithoutEcho(turn.audioBytes!);
    }
  }

  void clearConversation() => state = state.copyWith(turns: []);
}

final voiceConversationControllerProvider =
    AutoDisposeNotifierProvider<VoiceConversationController, VoiceConversationState>(VoiceConversationController.new);
