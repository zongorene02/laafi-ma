import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../data/records.dart';
import '../records/record_screens.dart';
import '../records/record_specs.dart';
import 'gentle_support.dart';

/// Hygiène et bien-être : humeur du jour en un geste (gros visages), journal
/// des humeurs, accès aux capsules « bien-être » et à l'exercice de respiration.
class WellbeingScreen extends ConsumerWidget {
  const WellbeingScreen({super.key});

  Future<void> _logMood(WidgetRef ref, String mood) async {
    final today = isoDate(DateTime.now());
    final existing = (ref.read(collectionProvider(Col.moods)).valueOrNull ?? const [])
        .where((m) => m['date'] == today)
        .firstOrNull;
    await ref.read(collectionProvider(Col.moods).notifier).save({...?existing, 'date': today, 'mood': mood});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final moods = ref.watch(collectionProvider(Col.moods)).valueOrNull ?? const [];
    final today = isoDate(DateTime.now());
    final todayMood = moods.where((m) => m['date'] == today).firstOrNull?['mood'];
    final lowMood = ref.watch(lowMoodStreakProvider);

    return LaafiScaffold(
      title: S.wellbeing,
      listenText: '${S.moodToday} Touchez un visage.',
      backTo: '/carnet',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lowMood) ...[const GentleSupportCard(), const SizedBox(height: AppSpacing.md)],
          Row(
            children: [
              Expanded(child: Text(S.moodToday, style: theme.textTheme.titleLarge)),
              const ListenButton(text: S.moodToday, compact: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (value, label) in moodChoices)
                Semantics(
                  button: true,
                  label: label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    onTap: () => _logMood(ref, value),
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        color: todayMood == value
                            ? AppTheme.leaf.withValues(alpha: 0.25)
                            : theme.colorScheme.surfaceContainer,
                        border: Border.all(color: todayMood == value ? AppTheme.leaf : Colors.transparent, width: 2),
                      ),
                      child: Text(label.split(' ').first, style: const TextStyle(fontSize: 34)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/learn?track=bien_etre'),
            icon: const Icon(Icons.headphones_rounded, size: 28),
            label: const Text(S.capsulesWellbeing),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/help/breathing'),
            icon: const Icon(Icons.air_rounded, size: 28),
            label: const Text(S.breathing),
          ),
          const SectionTitle('Mes humeurs'),
          for (final mood in moods.take(14))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RecordCard(spec: recordSpecs[Col.moods]!, record: mood),
            ),
        ],
      ),
    );
  }
}
