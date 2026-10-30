import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/data/phone_actions.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../help/data/help_repository.dart';
import '../data/agent_repository.dart';
import '../data/appointment_reminders.dart';
import 'agent_gate.dart';
import 'agent_providers.dart';

export 'agent_gate.dart';

/// Résumé : celui du serveur si joignable, sinon calculé sur le téléphone.
final agentSummaryProvider = FutureProvider.autoDispose<(AgentSummary, bool fromServer)>((ref) async {
  final repo = await ref.watch(agentRepositoryProvider.future);
  try {
    return (await repo.summary(), true);
  } catch (_) {
    return (await repo.localSummary(), false);
  }
});

final _lastSyncProvider = FutureProvider.autoDispose<String?>((ref) async {
  final repo = await ref.watch(agentRepositoryProvider.future);
  return repo.lastSync();
});

class AgentHomeScreen extends ConsumerStatefulWidget {
  const AgentHomeScreen({super.key});

  @override
  ConsumerState<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends ConsumerState<AgentHomeScreen> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final repo = await ref.read(agentRepositoryProvider.future);
      await repo.sync();
      // On profite de la connexion pour rafraîchir les listes de référence
      // utilisées hors connexion (signes de danger, annuaire).
      await ref.read(assistantRepositoryProvider).fetchDangerSigns('fr');
      await ref.read(helpRepositoryProvider).fetchServices();
      if (mounted) showSnack(context, S.syncDone);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      refreshAgentLists(ref);
      ref.invalidate(agentSummaryProvider);
      ref.invalidate(_lastSyncProvider);
      ref.invalidate(agentDangerSignsProvider);
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(agentSessionProvider).valueOrNull;
    final summary = ref.watch(agentSummaryProvider);
    final pending = ref.watch(agentPendingProvider).valueOrNull ?? 0;
    final lastSync = ref.watch(_lastSyncProvider).valueOrNull;
    final theme = Theme.of(context);

    PictoTile tile(IconData icon, String label, Color color, String path) =>
        PictoTile(icon: icon, label: label, color: color, listenText: label, onTap: () => context.push(path));

    return AgentGate(
      child: LaafiScaffold(
        title: S.agentTitle,
        listenText: 'Espace agent : bénéficiaires, visites, orientation, QR code, traduction.',
        actions: [
          IconButton(
            tooltip: S.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(agentSessionProvider.notifier).logout(),
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (user != null) Text(user.fullName ?? user.email ?? '', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: summary.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(e.toString()),
                  data: (data) {
                    final (s, fromServer) = data;
                    Widget stat(String label, int value) => Column(
                      children: [
                        Text(
                          '$value',
                          style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary),
                        ),
                        Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          fromServer ? S.summary : '${S.summary} (${S.offline.toLowerCase()})',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          alignment: WrapAlignment.spaceAround,
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.sm,
                          children: [
                            stat(S.beneficiaries, s.beneficiaries),
                            stat('Enceintes', s.pregnant),
                            stat('Visites (30 j)', s.visitsLast30Days),
                            stat('Orientations (30 j)', s.referralsLast30Days),
                            stat('Signes de danger (30 j)', s.dangerSignsLast30Days),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.sync_rounded, size: 28),
              label: Text(pending > 0 ? '${S.sync} · ${S.pendingSync(pending)}' : S.sync),
            ),
            if (lastSync != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Dernière synchronisation : ${frDate(parseTimestamp(lastSync)?.toLocal())} ${hhmm(parseTimestamp(lastSync)!.toLocal())}',
                  textAlign: TextAlign.center,
                ),
              ),
            const _RemindersSection(),
            const SizedBox(height: AppSpacing.md),
            TileGrid(
              children: [
                tile(Icons.groups_rounded, S.beneficiaries, AppTheme.leaf, '/agent/beneficiaries'),
                tile(Icons.fact_check_rounded, S.decisionAid, AppTheme.danger, '/agent/decision'),
                tile(Icons.shield_rounded, S.gbvReferral, AppTheme.danger, '/agent/gbv'),
                tile(Icons.qr_code_scanner_rounded, S.scanQr, AppTheme.terracotta, '/agent/scan'),
                tile(Icons.translate_rounded, '${S.translation} : texte', AppTheme.sky, '/agent/translate/text'),
                tile(
                  Icons.graphic_eq_rounded,
                  '${S.translation} : conversation',
                  AppTheme.plum,
                  '/agent/translate/voice',
                ),
                tile(Icons.mic_rounded, '${S.translation} : message vocal', AppTheme.amber, '/agent/translate/message'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// « Rappels à faire » : rendez-vous en retard ou dans les 7 jours, avec SMS
/// (message neutre, prêt dans l'application SMS de l'agent) et appel.
class _RemindersSection extends ConsumerWidget {
  const _RemindersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reminders = ref.watch(agentRemindersProvider).valueOrNull ?? const <AppointmentReminder>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(child: Text(S.remindersToDo, style: theme.textTheme.titleLarge)),
              const ListenButton(text: S.remindersToDoListen, compact: true),
            ],
          ),
        ),
        if (reminders.isEmpty) const InfoBanner(text: S.remindersEmpty),
        for (final reminder in reminders)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        reminder.overdue ? Icons.event_busy_rounded : Icons.event_rounded,
                        color: reminder.overdue ? AppTheme.danger : null,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          [
                            reminder.beneficiary['pseudonym']?.toString() ?? '',
                            frDate(reminder.date),
                            if (reminder.overdue) S.reminderOverdue,
                            ?S.appointmentReasons[reminder.beneficiary['next_appointment_reason']],
                          ].join(' · '),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (reminder.phone == null)
                    const Text(S.noPhoneNoted)
                  else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => openSmsComposer([reminder.phone!], appointmentReminderSms(reminder.date)),
                            icon: const Icon(Icons.sms_rounded),
                            label: const Text(S.sms),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.leaf,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => callNumber(reminder.phone!),
                            icon: const Icon(Icons.call_rounded),
                            label: const Text(S.call),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
