import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/security/pin_flags.dart';
import '../../../core/security/pin_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/pin_pad.dart';

/// Choix (ou changement) d'un code : saisie puis confirmation.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, required this.slot, this.fromSettings = false});

  final PinSlot slot;
  final bool fromSettings;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String? _first;
  String? _error;

  /// Code d'un profil 2 ou 3 pas encore créé : c'est un nouveau profil.
  bool _newProfile = false;

  @override
  void initState() {
    super.initState();
    if (widget.slot == PinSlot.real2 || widget.slot == PinSlot.real3) {
      ref.read(pinServiceProvider).has(widget.slot).then((exists) {
        if (mounted && !exists) setState(() => _newProfile = true);
      });
    }
  }

  String get _title => switch (widget.slot) {
    PinSlot.real => S.changePin,
    PinSlot.real2 || PinSlot.real3 => _newProfile ? S.profileAdd : S.changePin,
    PinSlot.decoy => S.decoyPin,
    PinSlot.help || PinSlot.help2 || PinSlot.help3 => S.helpCode,
  };

  Future<void> _submit(String pin) async {
    if (!PinService.isValidPin(pin)) {
      setState(() => _error = S.pinTooShort);
      return;
    }
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (_first != pin) {
      setState(() {
        _first = null;
        _error = S.pinMismatch;
      });
      return;
    }
    try {
      await ref.read(pinServiceProvider).set(widget.slot, pin);
      await ref.read(pinFlagsProvider.notifier).refresh();
      if (mounted) {
        showSnack(context, S.save);
        context.pop();
      }
    } on PinException catch (e) {
      setState(() {
        _first = null;
        _error = e.message == 'duplicate' ? S.pinMustDiffer : S.pinTooShort;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final explanation = switch (widget.slot) {
      PinSlot.real => S.createPinText,
      PinSlot.real2 || PinSlot.real3 => _newProfile ? S.profileNewPinText : S.createPinText,
      PinSlot.decoy => S.decoyText,
      PinSlot.help || PinSlot.help2 || PinSlot.help3 => S.helpCodeText,
    };
    return LaafiScaffold(
      title: _title,
      listenText: '$_title. $explanation',
      backTo: '/settings',
      body: Column(
        children: [
          Text(explanation, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          Text(
            _first == null ? S.createPinTitle : S.confirmPinTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          PinPad(key: ValueKey(_first == null), onSubmit: _submit, error: _error),
        ],
      ),
    );
  }
}
