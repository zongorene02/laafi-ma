import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/listen_button.dart';
import '../data/learn_repository.dart';
import '../domain/weekly_tip.dart';

/// Capsule de la semaine, prise UNIQUEMENT dans le cache (aucun appel réseau
/// pour l'accueil du carnet). `null` : rien d'affiché.
final weeklyTipProvider = FutureProvider.autoDispose<Capsule?>((ref) async {
  final cached = await ref.watch(learnRepositoryProvider).cached(ref.watch(langProvider));
  return cached == null ? null : weeklyTip(cached.$1, DateTime.now());
});

/// « Conseil de la semaine » : une capsule validée ; toucher l'ouvre.
class WeeklyTipCard extends ConsumerWidget {
  const WeeklyTipCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capsule = ref.watch(weeklyTipProvider).valueOrNull;
    if (capsule == null) return const SizedBox.shrink();
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final title = capsule.textIn(lang).title;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.leaf.withValues(alpha: 0.15),
          child: const Icon(Icons.tips_and_updates_rounded, color: AppTheme.leaf),
        ),
        title: Text(S.weeklyTip, style: theme.textTheme.titleSmall),
        subtitle: Text(title, style: theme.textTheme.titleMedium),
        trailing: ListenButton(
          text: title,
          compact: true,
          mode: ListenMode.content,
          contentLang: capsule.langShown(lang),
        ),
        onTap: () => context.push('/learn/capsule/${capsule.id}'),
      ),
    );
  }
}
