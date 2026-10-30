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

/// En-tête de « Mes règles » : estimation des prochaines règles (moyenne des
/// cycles notés) et retard éventuel, toujours étiquetés « estimation ».
class CycleHeader extends ConsumerWidget {
  const CycleHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(collectionProvider(Col.cycles)).valueOrNull ?? const [];
    final starts = records.map((r) => parseDate(r['start_date'])).whereType<DateTime>();
    final estimate = estimateCycle(starts, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => context.push(recordEditPath(Col.cycles), extra: {'start_date': isoDate(DateTime.now())}),
          icon: const Icon(Icons.water_drop_rounded, size: 28),
          label: const Text(S.addPeriod),
        ),
        const SizedBox(height: AppSpacing.md),
        if (estimate == null || estimate.nextStart == null)
          const InfoBanner(text: S.needTwoPeriods)
        else ...[
          BigValueCard(
            label: S.nextPeriodEstimate,
            value: frDate(estimate.nextStart),
            note: '${S.averageCycle} : ${estimate.averageLength} ${S.days} (${S.estimation.toLowerCase()})',
          ),
          if (estimate.isLate) ...[
            const SizedBox(height: AppSpacing.sm),
            BigValueCard(
              label: S.estimation,
              value: S.lateBy(estimate.daysLate),
              note: S.lateNote,
              color: AppTheme.danger,
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
