import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../data/records.dart';
import '../records/record_screens.dart';
import '../records/record_specs.dart';

/// Agenda en vue SEMAINE : rendez-vous et tâches santé, jour par jour.
/// Les visites prénatales prévues y apparaissent aussi.
class AgendaWeekScreen extends ConsumerStatefulWidget {
  const AgendaWeekScreen({super.key});

  @override
  ConsumerState<AgendaWeekScreen> createState() => _AgendaWeekScreenState();
}

class _AgendaWeekScreenState extends ConsumerState<AgendaWeekScreen> {
  DateTime _monday = mondayOf(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agenda = ref.watch(collectionProvider(Col.agenda)).valueOrNull ?? const [];
    final visits = ref.watch(collectionProvider(Col.prenatalVisits)).valueOrNull ?? const [];
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 0; i < 7; i++) DateTime(_monday.year, _monday.month, _monday.day + i)];

    List<(String, Map<String, dynamic>)> itemsOn(DateTime day) => [
      for (final r in agenda)
        if (parseDate(r['date']) == day) (Col.agenda, r),
      for (final v in visits)
        if (parseDate(v['date']) == day) (Col.prenatalVisits, v),
    ]..sort((a, b) => '${a.$2['time'] ?? ''}'.compareTo('${b.$2['time'] ?? ''}'));

    return LaafiScaffold(
      title: S.agenda,
      listenText: recordSpecs[Col.agenda]!.listenText,
      backTo: '/carnet',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_agenda',
        onPressed: () =>
            context.push(recordEditPath(Col.agenda), extra: {'kind': 'appointment', 'date': isoDate(today)}),
        icon: const Icon(Icons.add_rounded, size: 28),
        label: const Text(S.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kIsWeb) ...[
            const InfoBanner(text: S.webNoReminders, icon: Icons.notifications_off_rounded),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Semaine précédente',
                onPressed: () => setState(() => _monday = _monday.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left_rounded, size: 32),
              ),
              Expanded(
                child: Text(
                  '${frDate(days.first)} – ${frDate(days.last)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Semaine suivante',
                onPressed: () => setState(() => _monday = _monday.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right_rounded, size: 32),
              ),
            ],
          ),
          TextButton(onPressed: () => setState(() => _monday = mondayOf(today)), child: const Text(S.today)),
          for (final day in days) ...[
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: day == today
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '${weekdaysShort[day.weekday - 1]} ${frDate(day)}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final (collection, record) in itemsOn(day))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: RecordCard(spec: recordSpecs[collection]!, record: record),
              ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
