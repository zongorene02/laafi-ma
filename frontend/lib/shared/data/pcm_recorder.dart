import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'wav_utils.dart';

/// Enregistrement micro en PCM 16 kHz mono, rendu en .wav. Même format sur
/// Android et sur le web (le flux PCM est la seule voie commune aux deux).
class PcmRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  BytesBuilder? _buffer;

  bool get isRecording => _buffer != null;

  /// `false` si le micro est refusé ou occupé.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    try {
      _buffer = BytesBuilder();
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      _subscription = stream.listen((chunk) => _buffer?.add(chunk));
      return true;
    } catch (_) {
      _buffer = null;
      return false;
    }
  }

  /// Arrête et renvoie le .wav (ou `null` si rien n'a été enregistré).
  Future<Uint8List?> stop() async {
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    final pcm = _buffer?.toBytes();
    _buffer = null;
    return pcm == null || pcm.isEmpty ? null : wrapPcm16AsWav(pcm);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _recorder.stop();
    await _recorder.dispose();
  }
}
