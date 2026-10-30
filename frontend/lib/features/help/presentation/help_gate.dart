import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/security/pin_flags.dart';
import '../../../core/security/pin_service.dart';
import '../../../core/security/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/pin_pad.dart';
import '../../lock/lock_screen.dart';

/// Protège la page Aide par le code du profil ouvert, s'il a été choisi
/// (profils réels seulement). Le code est redemandé après chaque verrouillage.
class HelpGate extends ConsumerStatefulWidget {
  const HelpGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HelpGate> createState() => _HelpGateState();
}

class _HelpGateState extends ConsumerState<HelpGate> {
  String? _error;

  Future<void> _submit(String code) async {
    final limiter = ref.read(attemptLimiterProvider);
    if (!limiter.canTry) {
      setState(() => _error = S.tooManyAttempts(limiter.secondsLeft));
      return;
    }
    final slot = PhoneProfiles.helpSlot(ref.read(sessionProvider).profileIndex);
    if (await ref.read(pinServiceProvider).matches(slot, code)) {
      limiter.recordSuccess();
      ref.read(sessionProvider.notifier).unlockHelp();
    } else {
      limiter.recordFailure();
      if (mounted) setState(() => _error = S.wrongPin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final hasCode = ref.watch(pinFlagsProvider.select((f) => f.hasHelpCodeFor(session.profileIndex)));
    if (!hasCode || session.isDecoy || session.helpUnlocked) return widget.child;
    return LaafiScaffold(
      title: S.helpCodePrompt,
      listenText: S.helpCodePrompt,
      protectedArea: true,
      body: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Icon(Icons.shield_rounded, size: 56),
          const SizedBox(height: AppSpacing.md),
          PinPad(onSubmit: _submit, error: _error),
        ],
      ),
    );
  }
}
