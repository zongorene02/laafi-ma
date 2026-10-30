import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/network/api_client.dart';
import '../../../core/translation_engine.dart';

/// Un événement reçu du serveur pendant une conversation : soit un tour
/// complet transcrit+traduit (texte), soit l'audio synthétisé qui suit
/// immédiatement (voir le protocole documenté dans
/// `backend/services/core-service/app/main.py`, `ws_translate_voice`).
sealed class RealtimeTurnEvent {}

class RealtimeTurnText extends RealtimeTurnEvent {
  RealtimeTurnText({required this.sourceText, required this.translatedText});
  final String sourceText;
  final String translatedText;
}

class RealtimeTurnAudio extends RealtimeTurnEvent {
  RealtimeTurnAudio(this.bytes);
  final Uint8List bytes;
}

class RealtimeTurnError extends RealtimeTurnEvent {
  RealtimeTurnError(this.message);
  final String message;
}

/// Enveloppe fine autour du WebSocket `/ws/translate-voice` : convertit les
/// messages bruts (texte JSON ou binaire) en événements typés, et expose une
/// API simple (`sendAudioChunk`) qui masque le protocole exact au reste de
/// l'application.
class RealtimeTranslateSocket {
  RealtimeTranslateSocket._(this._channel);

  final WebSocketChannel _channel;
  final _eventsController = StreamController<RealtimeTurnEvent>.broadcast();

  Stream<RealtimeTurnEvent> get events => _eventsController.stream;

  static Future<RealtimeTranslateSocket> connect({
    required String token,
    required String sourceLang,
    required String targetLang,
    TranslationEngine engine = TranslationEngine.verified,
  }) async {
    final wsBaseUrl = apiBaseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsBaseUrl/ws/translate-voice?token=$token');
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;

    final socket = RealtimeTranslateSocket._(channel);
    socket._listen();
    channel.sink.add(jsonEncode({'source_lang': sourceLang, 'target_lang': targetLang, 'mode': engine.apiValue}));
    return socket;
  }

  void _listen() {
    _channel.stream.listen(
      (message) {
        if (message is String) {
          final decoded = jsonDecode(message) as Map<String, dynamic>;
          if (decoded.containsKey('error')) {
            _eventsController.add(RealtimeTurnError(decoded['error'] as String));
          } else {
            _eventsController.add(
              RealtimeTurnText(
                sourceText: decoded['source_text'] as String,
                translatedText: decoded['translated_text'] as String,
              ),
            );
          }
        } else if (message is List<int>) {
          _eventsController.add(RealtimeTurnAudio(Uint8List.fromList(message)));
        }
      },
      onError: (Object error) => _eventsController.add(RealtimeTurnError(error.toString())),
      onDone: () => _eventsController.close(),
    );
  }

  /// Audio brut PCM 16 bits signé, mono, 16 000 Hz — format attendu tel
  /// quel par le serveur (voir `SAMPLE_RATE` dans main.py).
  void sendAudioChunk(Uint8List pcm16Chunk) {
    _channel.sink.add(pcm16Chunk);
  }

  Future<void> close() => _channel.sink.close();
}
