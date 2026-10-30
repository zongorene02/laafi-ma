import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../data/listen_service.dart';

enum ListenMode { interface, content, private }

/// Bouton « Écouter » présent sur chaque écran : beaucoup d'utilisatrices ne
/// lisent pas, la voix est le premier moyen d'utiliser l'application.
class ListenButton extends ConsumerStatefulWidget {
  const ListenButton({
    super.key,
    required this.text,
    this.compact = false,
    this.mode = ListenMode.interface,
    this.contentLang,
  });

  final String text;
  final bool compact;
  final ListenMode mode;

  /// Langue du texte quand [mode] vaut [ListenMode.content].
  final String? contentLang;

  @override
  ConsumerState<ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends ConsumerState<ListenButton> {
  bool _busy = false;

  Future<void> _listen() async {
    setState(() => _busy = true);
    final service = ref.read(listenServiceProvider);
    try {
      switch (widget.mode) {
        case ListenMode.interface:
          await service.speak(widget.text);
        case ListenMode.content:
          await service.speakContent(widget.text, widget.contentLang ?? 'fr');
        case ListenMode.private:
          final ok = await service.speakPrivate(widget.text);
          if (!ok) throw Exception();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.listenUnavailable)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : const Icon(Icons.volume_up_rounded, size: 28);
    if (widget.compact) {
      return IconButton.filledTonal(
        tooltip: S.listen,
        iconSize: 28,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: _busy ? null : _listen,
        icon: icon,
      );
    }
    return FilledButton.tonalIcon(onPressed: _busy ? null : _listen, icon: icon, label: const Text(S.listen));
  }
}
