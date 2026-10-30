import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/security/session.dart';

class PickedMedia {
  const PickedMedia({required this.bytes, required this.name, required this.mime});

  final Uint8List bytes;
  final String name;
  final String mime;

  bool get isImage => mime.startsWith('image/');
}

String _mimeFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Sélecteurs de photo / fichier. Le verrouillage automatique est suspendu
/// pendant le choix (l'appareil photo met l'application en arrière-plan).
class MediaPickers {
  MediaPickers(this._ref);

  final Ref _ref;

  Future<PickedMedia?> pickImage({required bool camera}) {
    return _ref.read(sessionProvider.notifier).withoutAutoLock(() async {
      final file = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file == null) return null;
      final name = file.name.isEmpty ? 'photo.jpg' : file.name;
      return PickedMedia(bytes: await file.readAsBytes(), name: name, mime: file.mimeType ?? _mimeFor(name));
    });
  }

  Future<PickedMedia?> pickFile() {
    return _ref.read(sessionProvider.notifier).withoutAutoLock(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      final file = result?.files.single;
      if (file?.bytes == null) return null;
      return PickedMedia(bytes: file!.bytes!, name: file.name, mime: _mimeFor(file.name));
    });
  }
}

final mediaPickersProvider = Provider<MediaPickers>(MediaPickers.new);
