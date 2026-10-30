import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/languages.dart';
import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/security/pin_flags.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/listen_button.dart';
import '../../shared/widgets/pin_pad.dart';

enum _Step {
  language,
  consentRecord,
  consentStats,
  consentBackup,
  createPin,
  confirmPin,
  decoy,
  helpCode,
  disguise,
  done,
}

/// Premier lancement : langue, consentements (lus à voix haute et écrits),
/// code secret, options de protection. Chaque étape a son bouton « Écouter ».
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.language;
  String _lang = 'fr';
  bool _consentRecord = false;
  bool _statsOptIn = false;
  bool _consentBackup = false;
  bool _disguise = false;
  String? _firstPin;
  String? _error;
  bool _optionalPadOpen = false;

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
    _optionalPadOpen = false;
  });

  Future<void> _setLang(String code) async {
    setState(() => _lang = code);
    // La langue s'applique tout de suite : le bouton « Écouter » des étapes
    // suivantes parle déjà dans la langue choisie.
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(lang: code));
    _go(_Step.consentRecord);
  }

  Future<void> _createPin(String pin) async {
    if (!PinService.isValidPin(pin)) {
      setState(() => _error = S.pinTooShort);
      return;
    }
    _firstPin = pin;
    _go(_Step.confirmPin);
  }

  Future<void> _confirmPin(String pin) async {
    if (pin != _firstPin) {
      _firstPin = null;
      setState(() {
        _step = _Step.createPin;
        _error = S.pinMismatch;
      });
      return;
    }
    final pins = ref.read(pinServiceProvider);
    // Recommencer l'accueil efface d'éventuels anciens codes facultatifs.
    for (final slot in PinSlot.values) {
      if (slot != PinSlot.real) await pins.clear(slot);
    }
    await pins.set(PinSlot.real, pin);
    _go(_Step.decoy);
  }

  Future<void> _setOptional(PinSlot slot, String pin, _Step next) async {
    try {
      await ref.read(pinServiceProvider).set(slot, pin);
      _go(next);
    } on PinException catch (e) {
      setState(() => _error = e.message == 'duplicate' ? S.pinMustDiffer : S.pinTooShort);
    }
  }

  Future<void> _finish() async {
    await ref.read(pinFlagsProvider.notifier).refresh();
    await ref.read(sessionProvider.notifier).unlock(ProfileKind.real);
    await ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            onboarded: true,
            lang: _lang,
            consentRecord: _consentRecord,
            statsOptIn: _statsOptIn,
            consentBackup: _consentBackup,
            disguise: _disguise,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.formMaxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _buildStep(context)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case _Step.language:
        return _StepView(
          key: const ValueKey('lang'),
          icon: Icons.record_voice_over_rounded,
          title: S.onbChooseLang,
          text: S.onbLangNote,
          listen: S.onbChooseLangListen,
          children: [
            for (final lang in kSupportedLanguages)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(72)),
                  onPressed: () => _setLang(lang.code),
                  child: Text(lang.name, style: const TextStyle(fontSize: 22)),
                ),
              ),
          ],
        );
      case _Step.consentRecord:
        return _ConsentStep(
          key: const ValueKey('record'),
          icon: Icons.lock_person_rounded,
          title: S.consentRecordTitle,
          text: S.consentRecordText,
          onAnswer: (yes) {
            _consentRecord = yes;
            _go(_Step.consentStats);
          },
        );
      case _Step.consentStats:
        return _ConsentStep(
          key: const ValueKey('stats'),
          icon: Icons.bar_chart_rounded,
          title: S.consentStatsTitle,
          text: S.consentStatsText,
          onAnswer: (yes) {
            _statsOptIn = yes;
            _go(_Step.consentBackup);
          },
        );
      case _Step.consentBackup:
        return _ConsentStep(
          key: const ValueKey('backup'),
          icon: Icons.cloud_upload_rounded,
          title: S.consentBackupTitle,
          text: S.consentBackupText,
          onAnswer: (yes) {
            _consentBackup = yes;
            _go(_Step.createPin);
          },
        );
      case _Step.createPin:
        return _StepView(
          key: const ValueKey('pin1'),
          icon: Icons.pin_rounded,
          title: S.createPinTitle,
          text: S.createPinText,
          listen: '${S.createPinTitle}. ${S.createPinText}',
          children: [PinPad(onSubmit: _createPin, error: _error)],
        );
      case _Step.confirmPin:
        return _StepView(
          key: const ValueKey('pin2'),
          icon: Icons.pin_rounded,
          title: S.confirmPinTitle,
          listen: S.confirmPinTitle,
          children: [PinPad(onSubmit: _confirmPin, error: _error)],
        );
      case _Step.decoy:
        return _optionalCode(PinSlot.decoy, S.decoyTitle, S.decoyText, Icons.theater_comedy_rounded, _Step.helpCode);
      case _Step.helpCode:
        return _optionalCode(PinSlot.help, S.helpCodeTitle, S.helpCodeText, Icons.shield_rounded, _Step.disguise);
      case _Step.disguise:
        return _StepView(
          key: const ValueKey('disguise'),
          icon: Icons.calculate_rounded,
          title: S.disguiseTitle,
          text: S.disguiseText,
          listen: '${S.disguiseTitle}. ${S.disguiseText}',
          children: [
            FilledButton.icon(
              onPressed: () {
                _disguise = true;
                _go(_Step.done);
              },
              icon: const Icon(Icons.calculate_rounded),
              label: const Text(S.disguiseOn),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () {
                _disguise = false;
                _go(_Step.done);
              },
              icon: const Icon(Icons.lock_rounded),
              label: const Text(S.disguiseOff),
            ),
          ],
        );
      case _Step.done:
        return _StepView(
          key: const ValueKey('done'),
          icon: Icons.check_circle_rounded,
          title: S.onbDone,
          text: S.onbDoneText,
          listen: '${S.onbDone} ${S.onbDoneText}',
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              onPressed: _finish,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(S.start),
            ),
          ],
        );
    }
  }

  Widget _optionalCode(PinSlot slot, String title, String text, IconData icon, _Step next) {
    return _StepView(
      key: ValueKey(slot.name),
      icon: icon,
      title: title,
      text: text,
      listen: '$title. $text',
      children: [
        if (_optionalPadOpen)
          PinPad(onSubmit: (pin) => _setOptional(slot, pin, next), error: _error)
        else
          FilledButton.icon(
            onPressed: () => setState(() => _optionalPadOpen = true),
            icon: const Icon(Icons.pin_rounded),
            label: const Text(S.setThisCode),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(onPressed: () => _go(next), child: const Text(S.skip)),
      ],
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({
    super.key,
    required this.icon,
    required this.title,
    required this.listen,
    this.text,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String? text;
  final String listen;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Container(
            width: 110,
            height: 110,
            decoration: const BoxDecoration(gradient: AppTheme.brandGradient, shape: BoxShape.circle),
            child: Icon(icon, size: 60, color: Colors.white),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        if (text != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(text!, style: theme.textTheme.titleMedium?.copyWith(height: 1.5), textAlign: TextAlign.center),
        ],
        const SizedBox(height: AppSpacing.md),
        Center(child: ListenButton(text: listen)),
        const SizedBox(height: AppSpacing.lg),
        ...children,
      ],
    );
  }
}

class _ConsentStep extends StatelessWidget {
  const _ConsentStep({super.key, required this.icon, required this.title, required this.text, required this.onAnswer});

  final IconData icon;
  final String title;
  final String text;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    return _StepView(
      icon: icon,
      title: title,
      text: text,
      listen: '$title. $text',
      children: [
        FilledButton.icon(
          onPressed: () => onAnswer(true),
          icon: const Icon(Icons.thumb_up_alt_rounded),
          label: const Text(S.accept),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => onAnswer(false),
          icon: const Icon(Icons.thumb_down_alt_rounded),
          label: const Text(S.refuse),
        ),
      ],
    );
  }
}
