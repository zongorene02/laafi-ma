import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Change l'icône et le nom de l'application sur l'écran du téléphone
/// (« Calculatrice »). Android seulement ; derrière une interface pour que les
/// tests utilisent une doublure.
abstract class IconDisguise {
  /// `false` sur le web et hors Android : le réglage est alors caché.
  bool get supported;

  /// Renvoie `true` si le changement a été fait.
  Future<bool> setDisguised(bool disguised);
}

/// Implémentation Android : `MainActivity.kt` active l'alias `.CalculatorAlias`
/// et désactive l'alias par défaut (ou l'inverse), sans fermer l'application.
class MethodChannelIconDisguise implements IconDisguise {
  MethodChannelIconDisguise({MethodChannel? channel, bool? isAndroid})
    : _channel = channel ?? const MethodChannel(channelName),
      _isAndroid = isAndroid ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const channelName = 'bf.ztech.laafima/disguise';

  final MethodChannel _channel;
  final bool _isAndroid;

  @override
  bool get supported => _isAndroid;

  @override
  Future<bool> setDisguised(bool disguised) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('setIconDisguised', {'disguised': disguised}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final iconDisguiseProvider = Provider<IconDisguise>((ref) => MethodChannelIconDisguise());
