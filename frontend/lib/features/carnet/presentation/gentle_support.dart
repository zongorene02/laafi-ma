import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/listen_button.dart';
import '../data/records.dart';
import '../domain/wellbeing_calc.dart';

/// Plusieurs jours d'humeur basse de suite (journal des humeurs du profil).
final lowMoodStreakProvider = Provider.autoDispose<bool>((ref) {
  final moods = ref.watch(collectionProvider(Col.moods)).valueOrNull ?? const [];
  return hasLowMoodStreak(moods, DateTime.now());
});

const listeningPath = '/help/directory?filter=listening';
const breathingPath = '/help/breathing';

/// Les deux propositions : « Parler à quelqu'un » et « Respirer ».
class SupportButtons extends StatelessWidget {
  const SupportButtons({super.key, this.onChosen});

  /// Appelé avant d'ouvrir l'écran (fermer la feuille du bas, par exemple).
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () {
            onChosen?.call();
            router.push(listeningPath);
          },
          icon: const Icon(Icons.hearing_rounded, size: 28),
          label: const Text(S.listeningServices),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () {
            onChosen?.call();
            router.push(breathingPath);
          },
          icon: const Icon(Icons.air_rounded, size: 28),
          label: const Text(S.breathing),
        ),
      ],
    );
  }
}

/// Carte douce montrée quand l'humeur est basse plusieurs jours de suite.
/// Aucun conseil de santé : seulement deux portes ouvertes.
class GentleSupportCard extends StatelessWidget {
  const GentleSupportCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: AppTheme.leaf.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite_border_rounded, color: AppTheme.leaf, size: 32),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(S.gentleSupportTitle, style: theme.textTheme.titleMedium)),
                const ListenButton(text: '${S.gentleSupportTitle}. ${S.gentleSupportText}', compact: true),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(S.gentleSupportText, style: theme.textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.md),
            const SupportButtons(),
          ],
        ),
      ),
    );
  }
}

/// Feuille du bas proposée après une alerte préparée ou un appel d'aide.
Future<void> showSupportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(S.supportSheetTitle, style: Theme.of(sheetContext).textTheme.titleLarge)),
                const ListenButton(text: '${S.supportSheetTitle}. ${S.supportSheetText}', compact: true),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(S.supportSheetText),
            const SizedBox(height: AppSpacing.md),
            SupportButtons(onChosen: () => Navigator.of(sheetContext).pop()),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text(S.close)),
          ],
        ),
      ),
    ),
  );
}
