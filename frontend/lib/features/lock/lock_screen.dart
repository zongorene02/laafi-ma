import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/security/calculator_engine.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/listen_button.dart';
import '../../shared/widgets/pin_pad.dart';

/// Un seul limiteur pour toute l'application : changer d'écran ne remet pas
/// le compteur d'essais à zéro.
final attemptLimiterProvider = Provider<AttemptLimiter>((ref) => AttemptLimiter());

/// Écran NEUTRE affiché au démarrage et après chaque verrouillage : la
/// calculatrice si le camouflage est activé, sinon un simple écran de code
/// (sans nom ni image d'application de santé).
class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disguise = ref.watch(settingsProvider.select((s) => s.disguise));
    return disguise ? const CalculatorScreen() : const _PinLockView();
  }
}

/// Essaie d'ouvrir un profil avec [pin] (le profil réel dont c'est le code,
/// ou le leurre). Renvoie `false` si refusé.
Future<bool> tryUnlock(WidgetRef ref, String pin) async {
  final limiter = ref.read(attemptLimiterProvider);
  if (!limiter.canTry) return false;
  final outcome = await ref.read(pinServiceProvider).unlockProfile(pin);
  if (outcome.result == UnlockResult.invalid) {
    limiter.recordFailure();
    return false;
  }
  limiter.recordSuccess();
  // Téléphone partagé : le code dit QUEL profil s'ouvre, chacun son coffre.
  await ref
      .read(sessionProvider.notifier)
      .unlock(outcome.result == UnlockResult.real ? ProfileKind.real : ProfileKind.decoy, profile: outcome.profile);
  return true;
}

class _PinLockView extends ConsumerStatefulWidget {
  const _PinLockView();

  @override
  ConsumerState<_PinLockView> createState() => _PinLockViewState();
}

class _PinLockViewState extends ConsumerState<_PinLockView> {
  String? _error;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _submit(String pin) async {
    final limiter = ref.read(attemptLimiterProvider);
    if (!limiter.canTry) {
      setState(() => _error = S.tooManyAttempts(limiter.secondsLeft));
      return;
    }
    final ok = await tryUnlock(ref, pin);
    if (!mounted || ok) return;
    setState(() => _error = limiter.canTry ? S.wrongPin : S.tooManyAttempts(limiter.secondsLeft));
    if (!limiter.canTry) {
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        setState(() => _error = limiter.canTry ? null : S.tooManyAttempts(limiter.secondsLeft));
        if (limiter.canTry) timer.cancel();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(S.lockTitle, style: theme.textTheme.headlineMedium),
                    const SizedBox(width: AppSpacing.sm),
                    const ListenButton(text: S.lockListen, compact: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                PinPad(onSubmit: _submit, error: _error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Calculatrice de camouflage, entièrement fonctionnelle. « code secret puis
/// = » ouvre l'application ; un mauvais code affiche simplement le nombre,
/// sans aucun message qui trahirait l'existence d'un code.
class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  final _engine = CalculatorEngine();

  Future<void> _press(String key) async {
    final candidate = _engine.press(key);
    setState(() {});
    if (candidate != null) await tryUnlock(ref, candidate);
  }

  @override
  Widget build(BuildContext context) {
    const rows = [
      [CalculatorEngine.clear, CalculatorEngine.backspace, CalculatorEngine.divide, CalculatorEngine.times],
      ['7', '8', '9', CalculatorEngine.minus],
      ['4', '5', '6', CalculatorEngine.plus],
      ['1', '2', '3', CalculatorEngine.equals],
      ['0', CalculatorEngine.dot],
    ];
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.dark);
    return Theme(
      data: ThemeData(colorScheme: scheme, useMaterial3: true),
      child: Scaffold(
        backgroundColor: const Color(0xFF111418),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      alignment: Alignment.bottomRight,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _engine.pendingOperator ?? '',
                            style: const TextStyle(color: Colors.white54, fontSize: 28),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _engine.display,
                              style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w300),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final row in rows)
                    Row(
                      children: [
                        for (final key in row)
                          Expanded(
                            flex: key == '0' ? 3 : 1,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: SizedBox(
                                height: 72,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: CalculatorEngine.operators.contains(key) || key == '='
                                        ? const Color(0xFFFF9F0A)
                                        : (key == 'C' || key == '⌫')
                                        ? const Color(0xFF5A5F66)
                                        : const Color(0xFF2C3036),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
                                  ),
                                  onPressed: () => _press(key),
                                  child: Text(key, style: const TextStyle(fontSize: 28)),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
