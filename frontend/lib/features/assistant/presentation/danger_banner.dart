import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/phone_actions.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../help/data/help_repository.dart';
import '../../stats/stats_service.dart';
import '../data/assistant_models.dart';

/// Bandeau rouge des signes de danger, avec trois boutons d'appel (centre de
/// santé, urgences, numéro vert). Les numéros
/// viennent UNIQUEMENT de l'annuaire validé (`GET /help/services`, gardé en
/// cache) : aucun numéro n'est écrit dans l'application.
class DangerBanner extends ConsumerWidget {
  const DangerBanner({super.key, required this.signs, required this.contentLang});

  final List<DangerSignHit> signs;
  final String contentLang;

  Future<void> _call(BuildContext context, WidgetRef ref, bool Function(HelpService) test) async {
    final repo = ref.read(helpRepositoryProvider);
    var service = await repo.firstCached(test);
    if (service == null) {
      try {
        await repo.fetchServices();
        service = await repo.firstCached(test);
      } catch (_) {
        // Hors connexion et rien en cache : message ci-dessous.
      }
    }
    if (service == null) {
      if (context.mounted) showSnack(context, S.noNumberCached);
      return;
    }
    await ref.read(statsServiceProvider).track(StatEvent.helpCall);
    await callNumber(service.phone);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spoken = [S.dangerTitle, for (final s in signs) '${s.label}. ${s.advice}'].join('. ');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.danger, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 40),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(S.dangerTitle, style: theme.textTheme.titleLarge?.copyWith(color: AppTheme.danger)),
              ),
              ListenButton(text: spoken, compact: true, mode: ListenMode.content, contentLang: contentLang),
            ],
          ),
          for (final sign in signs) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(sign.label, style: theme.textTheme.titleMedium),
            Text(sign.advice, style: theme.textTheme.bodyLarge),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () => _call(context, ref, (s) => s.category == 'health'),
            icon: const Icon(Icons.local_hospital_rounded, size: 28),
            label: const Text(S.callHealthCenter),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () => _call(context, ref, (s) => s.category == 'emergency'),
            icon: const Icon(Icons.emergency_rounded, size: 28),
            label: const Text(S.callEmergency),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _call(context, ref, (s) => s.category == 'hotline' && s.freeCall),
            icon: const Icon(Icons.phone_in_talk_rounded, size: 28),
            label: const Text(S.callHotline),
          ),
        ],
      ),
    );
  }
}
