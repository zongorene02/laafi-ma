import 'package:flutter/material.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';

/// Clavier de code à gros chiffres, utilisable sans savoir lire : des points
/// montrent combien de chiffres ont été tapés, ✓ valide.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onSubmit, this.error, this.enabled = true, this.minLength = 4});

  final Future<void> Function(String pin) onSubmit;
  final String? error;
  final bool enabled;
  final int minLength;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  static const _maxLength = 6;
  String _pin = '';
  bool _busy = false;

  void _tap(String digit) {
    if (_pin.length >= _maxLength) return;
    setState(() => _pin += digit);
  }

  void _erase() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_pin.length < widget.minLength || _busy) return;
    setState(() => _busy = true);
    final pin = _pin;
    try {
      await widget.onSubmit(pin);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.enabled && !_busy;
    Widget key(Widget child, VoidCallback? onTap, {String? label, Color? color}) => Padding(
      padding: const EdgeInsets.all(6),
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: 76,
          height: 76,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: color,
              minimumSize: const Size(76, 76),
            ),
            onPressed: enabled ? onTap : null,
            child: child,
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _maxLength; i++)
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? theme.colorScheme.primary : Colors.transparent,
                  border: Border.all(color: theme.colorScheme.outline, width: 2),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 40,
          child: Center(
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(
                    widget.error ?? '',
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
          ),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in row) key(Text(d, style: theme.textTheme.headlineMedium), () => _tap(d), label: d),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key(const Icon(Icons.backspace_outlined, size: 28), _erase, label: 'Effacer'),
            key(Text('0', style: theme.textTheme.headlineMedium), () => _tap('0'), label: '0'),
            key(
              Icon(Icons.check_rounded, size: 34, color: theme.colorScheme.onPrimary),
              _pin.length >= widget.minLength ? _submit : null,
              label: S.ok,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}
