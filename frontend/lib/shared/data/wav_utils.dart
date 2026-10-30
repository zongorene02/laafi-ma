import 'dart:typed_data';

/// Encapsule du PCM 16 bits brut (tel que fourni par `record.startStream()`,
/// voir `realtime_translate_socket.dart` pour le même format côté
/// conversation en direct) dans un conteneur .wav minimal mais valide —
/// nécessaire car les endpoints REST (contrairement au WebSocket) attendent
/// un vrai FICHIER audio, que core-service décode ensuite via ffmpeg.
///
/// Format : en-tête WAV standard de 44 octets (RIFF/WAVE/fmt /data),
/// suffisant pour du PCM non compressé — pas besoin d'une bibliothèque
/// tierce pour ça, le format est simple et stable depuis les années 1990.
Uint8List wrapPcm16AsWav(Uint8List pcmData, {int sampleRate = 16000, int numChannels = 1}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = pcmData.length;

  final header = ByteData(44);
  void writeString(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // taille du sous-bloc fmt
  header.setUint16(20, 1, Endian.little); // format PCM (non compressé)
  header.setUint16(22, numChannels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  writeString(36, 'data');
  header.setUint32(40, dataSize, Endian.little);

  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcmData]);
}
