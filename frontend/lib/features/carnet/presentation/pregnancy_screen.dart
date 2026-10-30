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

/// Pick a date and save it as a single-document field.
Future<void> pickAndSaveDate(
  BuildContext context,
  WidgetRef ref, {
  required String collection,
  required String field,
  DateTime? initial,
  int maxDaysBack = 400,
}) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: now.subtract(Duration(days: maxDaysBack)),
    lastDate: now,
  );
  if (picked == null) return;
  await ref.read(collectionProvider(collection).notifier).save({'id': 'current', field: isoDate(picked)});
}

class PregnancyScreen extends ConsumerWidget {
  const PregnancyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(collectionProvider(Col.pregnancy)).valueOrNull?.firstOrNull;
    final lmp = parseDate(record?['lmp']);
    final estimate = lmp == null ? null : pregnancyFromLmp(lmp, DateTime.now());

    Widget link(IconData icon, String label, String specId) => Card(
      child: ListTile(
        leading: Icon(icon, size: 32, color: AppTheme.terracotta),
        title: Text(label, style: Theme.of(context).textTheme.titleMedium),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push(recordListPath(specId)),
      ),
    );

    return LaafiScaffold(
      title: S.pregnancy,
      listenText:
          'Grossesse. Notez le premier jour de vos dernières règles. Le téléphone estime la semaine de grossesse '
          'et la date prévue d\'accouchement. Seul un soignant peut confirmer.',
      backTo: '/carnet',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_rounded, size: 32),
              title: const Text(S.lmp),
              subtitle: Text(lmp == null ? S.chooseDate : frDate(lmp), style: Theme.of(context).textTheme.titleLarge),
              onTap: () => pickAndSaveDate(context, ref, collection: Col.pregnancy, field: 'lmp', initial: lmp),
            ),
          ),
          if (estimate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            BigValueCard(
              label: S.pregnancyWeek,
              value: '${estimate.weeks} semaines${estimate.days > 0 ? ' et ${estimate.days} jours' : ''}',
              note: S.naegeleNote,
            ),
            const SizedBox(height: AppSpacing.sm),
            BigValueCard(label: S.dueDate, value: frDate(estimate.dueDate), note: S.naegeleNote, color: AppTheme.leaf),
          ],
          const SizedBox(height: AppSpacing.md),
          link(Icons.pregnant_woman_rounded, S.prenatalVisits, Col.prenatalVisits),
          link(Icons.biotech_rounded, S.exams, Col.exams),
          link(Icons.monitor_weight_rounded, S.weight, Col.weights),
          link(Icons.favorite_rounded, S.bloodPressure, Col.bloodPressure),
          if (record != null) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () async {
                if (!await confirmDialog(context, '${S.endPregnancy} ?')) return;
                await ref.read(collectionProvider(Col.pregnancy).notifier).remove('current');
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text(S.endPregnancy),
            ),
          ],
        ],
      ),
    );
  }
}
