import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lecteur audio partagé : une nouvelle lecture interrompt la précédente.
/// Sert à la fois aux octets reçus (synthèse vocale, audio en cache, notes
/// vocales) et aux URL `/media/...` servies par l'API.
class AudioPlaybackService {
  AudioPlaybackService() : _player = AudioPlayer();

  final AudioPlayer _player;

  Stream<void> get onPlaybackComplete => _player.onPlayerComplete;

  Future<void> play(Uint8List bytes, {String mimeType = 'audio/wav'}) async {
    await _player.stop();
    await _player.play(BytesSource(bytes, mimeType: mimeType));
  }

  Future<void> playUrl(String url) async {
    await _player.stop();
    await _player.play(UrlSource(url));
  }

  /// Lit l'extrait ET attend qu'il soit terminé.
  Future<void> playAndWait(Uint8List bytes) async {
    final completed = _player.onPlayerComplete.first;
    await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    await completed;
  }

  Future<void> stop() => _player.stop();

  void dispose() => _player.dispose();
}

final audioPlaybackServiceProvider = Provider<AudioPlaybackService>((ref) {
  final service = AudioPlaybackService();
  ref.onDispose(service.dispose);
  return service;
});
