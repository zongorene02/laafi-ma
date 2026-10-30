import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../help/data/help_repository.dart';
import '../data/agent_repository.dart';
import '../data/sync_merge.dart';
import 'agent_gate.dart';
import 'agent_providers.dart';

const gbvCategories = {
  'physical': 'Physique',
  'sexual': 'Sexuelle',
  'psychological': 'Psychologique',
  'economic': 'Économique',
  'early_marriage': 'Mariage précoce',
  'fgm': 'Excision',
  'other': 'Autre',
};

final _cachedServicesProvider = FutureProvider.autoDispose<List<HelpService>>((ref) async {
  return (await ref.watch(helpRepositoryProvider).cachedServices())?.$1 ?? const [];
});

/// Orientation VBG ANONYME : date, type, service. Jamais de nom ni
/// d'identifiant de bénéficiaire (règle 4 de docs/API.md).
class GbvReferralScreen extends ConsumerStatefulWidget {
  const GbvReferralScreen({super.key});

  @override
  ConsumerState<GbvReferralScreen> createState() => _GbvReferralScreenState();
}

class _GbvReferralScreenState extends ConsumerState<GbvReferralScreen> {
  String _date = isoDate(DateTime.now());
  String? _category;
  String? _serviceId;

  Future<void> _save() async {
    if (_category == null) {
      showSnack(context, 'Choisissez le type.');
      return;
    }
    final repo = await ref.read(agentRepositoryProvider.future);
    await repo.save(AgentCollections.gbvReferrals, {
      'id': const Uuid().v4(),
      'referral_date': _date,
      'service_id': _serviceId,
      'category': _category,
    });
    refreshAgentLists(ref);
    setState(() {
      _category = null;
      _serviceId = null;
    });
    if (mounted) showSnack(context, 'Orientation enregistrée.');
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(_cachedServicesProvider).valueOrNull ?? const [];
    final referrals = ref.watch(agentListProvider(AgentCollections.gbvReferrals)).valueOrNull ?? const [];
    final theme = Theme.of(context);
    String serviceName(Object? id) => services.where((s) => s.id == id).firstOrNull?.name ?? '—';

    return AgentGate(
      child: LaafiScaffold(
        title: S.gbvReferral,
        backTo: '/agent',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InfoBanner(text: S.gbvNoName, icon: Icons.privacy_tip_rounded),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_rounded),
                title: const Text('Date'),
                subtitle: Text(frDate(_date), style: theme.textTheme.titleMedium),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: parseDate(_date) ?? now,
                    firstDate: now.subtract(const Duration(days: 365)),
                    lastDate: now,
                  );
                  if (picked != null) setState(() => _date = isoDate(picked));
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Type de violence', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in gbvCategories.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _category == entry.key,
                    onSelected: (_) => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              initialValue: _serviceId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Service vers lequel elle est orientée'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Non précisé')),
                for (final s in services)
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(
                      '${s.name} (${helpCategoryLabels[s.category] ?? s.category})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _serviceId = v),
            ),
            if (services.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xs),
                child: Text('Annuaire non téléchargé : synchronisez avec internet.'),
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: const Text(S.save)),
            const SectionTitle('Orientations enregistrées', listen: false),
            for (final r in referrals.take(20))
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_rounded, color: AppTheme.danger),
                  title: Text('${gbvCategories[r['category']] ?? r['category']} · ${frDate(r['referral_date'])}'),
                  subtitle: Text(serviceName(r['service_id'])),
                  trailing: r[dirtyFlag] == true ? const Icon(Icons.cloud_upload_outlined) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
