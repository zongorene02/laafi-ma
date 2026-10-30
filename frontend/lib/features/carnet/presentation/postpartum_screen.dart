import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../data/records.dart';
import '../domain/health_calc.dart';
import '../records/record_screens.dart';
import '../records/record_specs.dart';
import 'pregnancy_screen.dart';

/// Suivi après l'accouchement, jusqu'au 42e jour : allaitement et humeur.
class PostpartumScreen extends ConsumerWidget {
  const PostpartumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final record = ref.watch(collectionProvider(Col.postpartum)).valueOrNull?.firstOrNull;
    final delivery = parseDate(record?['delivery_date']);
    final day = delivery == null ? null : postpartumDay(delivery, DateTime.now());
    final logs = ref.watch(collectionProvider(Col.postpartumLogs)).valueOrNull ?? const [];

    return LaafiScaffold(
      title: S.postpartum,
      listenText:
          'Après l\'accouchement. Notez la date de l\'accouchement, puis chaque jour l\'allaitement et votre humeur, '
          'jusqu\'au 42e jour.',
      backTo: '/carnet',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_rounded, size: 32),
              title: const Text(S.deliveryDate),
              subtitle: Text(delivery == null ? S.chooseDate : frDate(delivery), style: theme.textTheme.titleLarge),
              onTap: () => pickAndSaveDate(
                context,
                ref,
                collection: Col.postpartum,
                field: 'delivery_date',
                initial: delivery,
                maxDaysBack: 365,
              ),
            ),
          ),
          if (day != null) ...[
            const SizedBox(height: AppSpacing.sm),
            BigValueCard(
              label: S.postpartum,
              value: S.postpartumDay(day),
              note: day > postpartumFollowUpDays ? S.postpartumDone : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: (day / postpartumFollowUpDays).clamp(0, 1).toDouble(),
              minHeight: 12,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            const SizedBox(height: AppSpacing.md),
            if (day <= postpartumFollowUpDays)
              FilledButton.icon(
                onPressed: () =>
                    context.push(recordEditPath(Col.postpartumLogs), extra: {'date': isoDate(DateTime.now())}),
                icon: const Icon(Icons.edit_note_rounded, size: 28),
                label: const Text(S.postpartumLogs),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final log in logs.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RecordCard(spec: recordSpecs[Col.postpartumLogs]!, record: log),
            ),
          if (logs.length > 10)
            TextButton(
              onPressed: () => context.push(recordListPath(Col.postpartumLogs)),
              child: const Text('Tout voir'),
            ),
        ],
      ),
    );
  }
}
