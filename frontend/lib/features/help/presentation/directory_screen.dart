import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/data/phone_actions.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../carnet/presentation/gentle_support.dart';
import '../../stats/stats_service.dart';
import '../data/help_repository.dart';
import 'help_gate.dart';

final helpServicesProvider = FutureProvider.autoDispose<(List<HelpService>, bool)>((ref) {
  return ref.watch(helpRepositoryProvider).load();
});

const _listeningCategories = {'psychosocial', 'hotline', 'vbg_center'};

/// Annuaire des services d'aide (`GET /help/services`), gardé en cache pour
/// appeler même sans internet. Un numéro non vérifié est TOUJOURS signalé.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key, this.listeningOnly = false});

  /// « Parler à quelqu'un » : écoute psychologique, numéros verts, centres VBG.
  final bool listeningOnly;

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  String? _category;
  String? _city;

  @override
  void initState() {
    super.initState();
    ref.read(statsServiceProvider).track(StatEvent.directoryViewed);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(helpServicesProvider);
    final theme = Theme.of(context);
    return HelpGate(
      child: LaafiScaffold(
        title: widget.listeningOnly ? S.listeningServices : S.directory,
        listenText: S.directoryListen,
        protectedArea: true,
        backTo: '/help',
        body: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorRetry(message: e.toString(), onRetry: () => ref.invalidate(helpServicesProvider)),
          data: (data) {
            final (all, fromCache) = data;
            final base = widget.listeningOnly
                ? all.where((s) => _listeningCategories.contains(s.category)).toList()
                : all;
            final categories = {for (final s in base) s.category}.toList()..sort();
            final cities = {for (final s in base) ?s.city}.toList()..sort();
            final shown = base
                .where((s) => _category == null || s.category == _category)
                .where((s) => _city == null || s.city == _city)
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fromCache) ...[
                  const InfoBanner(text: '${S.offline} · ${S.offlineData}', icon: Icons.wifi_off_rounded),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const InfoBanner(text: S.callLogNote, icon: Icons.history_rounded),
                const SizedBox(height: AppSpacing.sm),
                if (categories.length > 1)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      ChoiceChip(
                        label: const Text('Tout'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      for (final c in categories)
                        ChoiceChip(
                          label: Text(helpCategoryLabels[c] ?? c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                    ],
                  ),
                if (cities.length > 1) ...[
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String?>(
                    initialValue: _city,
                    decoration: const InputDecoration(
                      labelText: 'Ville',
                      prefixIcon: Icon(Icons.location_city_rounded),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Toutes')),
                      for (final city in cities) DropdownMenuItem<String?>(value: city, child: Text(city)),
                    ],
                    onChanged: (value) => setState(() => _city = value),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                if (shown.isEmpty) const InfoBanner(text: S.empty),
                for (final service in shown) _ServiceCard(service: service, theme: theme),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.service, required this.theme});

  final HelpService service;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = [
      helpCategoryLabels[service.category] ?? service.category,
      ?service.city,
      ?service.hours,
    ].join(' · ');
    final spoken = '${service.name}. $details. ${service.verified ? '' : S.notConfirmed}';
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(service.name, style: theme.textTheme.titleMedium)),
                ListenButton(text: spoken, compact: true),
              ],
            ),
            Text(details, style: theme.textTheme.bodyMedium),
            if (service.address != null) Text(service.address!, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (!service.verified)
                  Chip(
                    avatar: const Icon(Icons.help_outline_rounded, size: 18),
                    label: const Text(S.notConfirmed),
                    backgroundColor: AppTheme.amber.withValues(alpha: 0.25),
                  )
                else
                  Chip(
                    avatar: const Icon(Icons.verified_rounded, size: 18),
                    label: Text('Vérifié le ${frDate(service.verifiedAt)}'),
                  ),
                if (service.freeCall) const Chip(label: Text(S.freeCall)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.leaf, foregroundColor: Colors.white),
              onPressed: () async {
                await ref.read(statsServiceProvider).track(StatEvent.helpCall);
                final called = await callNumber(service.phone);
                if (called && context.mounted) await showSupportSheet(context);
              },
              icon: const Icon(Icons.call_rounded, size: 28),
              label: Text('${S.call} ${service.phone}'),
            ),
          ],
        ),
      ),
    );
  }
}
