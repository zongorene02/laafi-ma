import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/security/phone_profiles.dart';
import '../../../core/security/pin_flags.dart';
import '../../../core/security/secret_phrase.dart';
import '../../../core/security/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../../shared/widgets/pin_pad.dart';
import '../../lock/lock_screen.dart';

/// « Profils (téléphone partagé) » : jusqu'à 3 profils réels, chacun avec son
/// code et son coffre. Le profil 1 est celui de la propriétaire du téléphone.
class ProfilesCard extends ConsumerWidget {
  const ProfilesCard({super.key});

  /// Demande le code du profil [profile] (on ne retire pas le profil d'une
  /// autre personne sans son code). Même limite d'essais que l'écran du code.
  Future<bool> _askProfilePin(BuildContext context, WidgetRef ref, int profile) async {
    final pins = ref.read(pinServiceProvider);
    final limiter = ref.read(attemptLimiterProvider);
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(S.profileRemovePin),
          content: SingleChildScrollView(
            child: PinPad(
              error: error,
              onSubmit: (pin) async {
                if (!limiter.canTry) {
                  setDialogState(() => error = S.tooManyAttempts(limiter.secondsLeft));
                  return;
                }
                if (await pins.matches(PhoneProfiles.pinSlot(profile), pin)) {
                  limiter.recordSuccess();
                  if (context.mounted) Navigator.pop(context, true);
                } else {
                  limiter.recordFailure();
                  setDialogState(() => error = S.wrongPin);
                }
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(S.cancel))],
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, int profile) async {
    final current = ref.read(sessionProvider).profileIndex;
    if (profile != current && !await _askProfilePin(context, ref, profile)) return;
    if (!context.mounted) return;
    if (!await confirmDialog(context, S.profileRemoveConfirm, confirmLabel: S.profileRemove)) return;
    // Tout est récupéré AVANT un éventuel verrouillage (l'écran disparaît).
    final pins = ref.read(pinServiceProvider);
    final vault = ref.read(vaultProvider);
    final phrases = ref.read(secretPhraseStoreProvider);
    final flags = ref.read(pinFlagsProvider.notifier);
    if (profile == current) {
      ref.read(sessionProvider.notifier).lock();
      if (context.mounted) GoRouter.of(context).go('/lock');
    }
    await removePhoneProfile(profile: profile, pins: pins, vault: vault, phrases: phrases);
    await flags.refresh();
    if (profile != current && context.mounted) showSnack(context, S.profileRemoved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profiles = ref.watch(pinFlagsProvider.select((f) => f.profiles)).toList()..sort();
    final current = ref.watch(sessionProvider.select((s) => s.profileIndex));
    final next = nextFreeProfile(profiles);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.groups_rounded),
            title: Text(S.profilesTitle, style: theme.textTheme.titleMedium),
            subtitle: const Text(S.profilesText),
            trailing: const ListenButton(text: '${S.profilesTitle}. ${S.profilesText}', compact: true),
          ),
          for (final profile in profiles)
            ListTile(
              leading: Icon(profile == current ? Icons.person_pin_rounded : Icons.person_outline_rounded, size: 32),
              title: Text(S.profileName(profile)),
              subtitle: profile == current ? const Text(S.profileCurrent) : null,
              trailing: profile == 1
                  ? null
                  : TextButton(onPressed: () => _remove(context, ref, profile), child: const Text(S.remove)),
            ),
          if (next != null)
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded, size: 32),
              title: const Text(S.profileAdd),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/settings/pin/${PhoneProfiles.pinSlot(next).name}'),
            )
          else
            const ListTile(leading: Icon(Icons.info_outline_rounded), title: Text(S.profileMax)),
        ],
      ),
    );
  }
}

/// Phrase d'aide secrète du profil ouvert : jamais affichée une fois choisie.
class HelpPhraseTile extends ConsumerStatefulWidget {
  const HelpPhraseTile({super.key});

  @override
  ConsumerState<HelpPhraseTile> createState() => _HelpPhraseTileState();
}

class _HelpPhraseTileState extends ConsumerState<HelpPhraseTile> {
  bool _isSet = false;

  int get _profile => ref.read(sessionProvider).profileIndex;

  @override
  void initState() {
    super.initState();
    ref.read(secretPhraseStoreProvider).read(_profile).then((phrase) {
      if (mounted) setState(() => _isSet = phrase != null);
    });
  }

  Future<void> _edit() async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(S.helpPhrase),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(S.helpPhraseText),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: controller,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(hintText: S.helpPhraseHint, errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
            FilledButton(
              onPressed: () {
                if (!isValidSecretPhrase(controller.text)) {
                  setDialogState(() => error = S.helpPhraseTooShort);
                  return;
                }
                Navigator.pop(context, controller.text.trim());
              },
              child: const Text(S.save),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    await ref.read(secretPhraseStoreProvider).write(_profile, result);
    if (!mounted) return;
    setState(() => _isSet = true);
    showSnack(context, S.helpPhraseSaved);
  }

  Future<void> _clear() async {
    if (!await confirmDialog(context, '${S.remove} ?', confirmLabel: S.remove)) return;
    await ref.read(secretPhraseStoreProvider).clear(_profile);
    if (mounted) setState(() => _isSet = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.record_voice_over_rounded),
      title: const Text(S.helpPhrase),
      subtitle: Text(_isSet ? '${S.helpPhraseIsSet}. ${S.helpPhraseText}' : S.helpPhraseText),
      trailing: _isSet ? TextButton(onPressed: _clear, child: const Text(S.remove)) : null,
      onTap: _edit,
    );
  }
}
