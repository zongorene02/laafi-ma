import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../data/agent_repository.dart';
import 'agent_gate.dart';
import 'agent_providers.dart';
import 'beneficiary_screens.dart';
import 'decision_aid_screen.dart';

/// Visite : type, signes de danger cochés (liste validée de l'API) et
/// conseil d'orientation tiré des conseils validés de chaque signe.
class VisitFormScreen extends ConsumerStatefulWidget {
  const VisitFormScreen({super.key, required this.beneficiaryId, this.id});

  final String beneficiaryId;
  final String? id;

  @override
  ConsumerState<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends ConsumerState<VisitFormScreen> {
  final _referredTo = TextEditingController();
  final _notes = TextEditingController();
  Map<String, dynamic>? _existing;
  String _date = isoDate(DateTime.now());
  String _type = 'follow_up';
  final Set<String> _signs = {};
  bool _referred = false;
  bool _loaded = false;

  @override
  void dispose() {
    _referredTo.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _load(List<Map<String, dynamic>> visits) {
    if (_loaded) return;
    _loaded = true;
    final v = visits.where((r) => r['id'] == widget.id).firstOrNull;
    if (v == null) return;
    _existing = v;
    _date = v['visit_date'] as String? ?? _date;
    _type = v['type'] as String? ?? _type;
    _signs.addAll((v['danger_sign_ids'] as List? ?? const []).map((e) => e.toString()));
    _referred = v['referred'] == true;
    _referredTo.text = v['referred_to'] as String? ?? '';
    _notes.text = v['notes'] as String? ?? '';
  }

  Future<void> _save() async {
    final repo = await ref.read(agentRepositoryProvider.future);
    String? blank(String text) => text.trim().isEmpty ? null : text.trim();
    await repo.save(AgentCollections.visits, {
      'id': _existing?['id'] ?? const Uuid().v4(),
      'beneficiary_id': widget.beneficiaryId,
      'visit_date': _date,
      'type': _type,
      'danger_sign_ids': _signs.toList(),
      'referred': _referred,
      'referred_to': _referred ? blank(_referredTo.text) : null,
      'notes': blank(_notes.text),
      'deleted': false,
    });
    refreshAgentLists(ref);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final visits = ref.watch(agentListProvider(AgentCollections.visits));
    final signs = ref.watch(agentDangerSignsProvider);
    if (!visits.hasValue) {
      return const AgentGate(
        child: LaafiScaffold(
          title: S.visits,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    _load(visits.value!);
    final theme = Theme.of(context);
    final checked = (signs.valueOrNull ?? const []).where((s) => _signs.contains(s.id)).toList();

    return AgentGate(
      child: LaafiScaffold(
        title: S.visits,
        backTo: '/agent/beneficiaries',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_rounded),
                title: const Text('Date de la visite'),
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
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in visitTypes.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _type == entry.key,
                    onSelected: (_) => setState(() => _type = entry.key),
                  ),
              ],
            ),
            const SectionTitle(S.dangerChecklist, listen: false),
            signs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(message: e.toString()),
              data: (list) => list.isEmpty
                  ? const InfoBanner(text: S.noDangerSignsCached)
                  : Column(
                      children: [
                        for (final sign in list)
                          CheckboxListTile(
                            value: _signs.contains(sign.id),
                            title: Text(sign.label),
                            onChanged: (v) => setState(() {
                              v == true ? _signs.add(sign.id) : _signs.remove(sign.id);
                              if (_signs.isNotEmpty) _referred = true;
                            }),
                          ),
                      ],
                    ),
            ),
            if (checked.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(
                text: S.referAdvice,
                icon: Icons.warning_amber_rounded,
                color: AppTheme.danger,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final sign in checked)
                      Row(
                        children: [
                          Expanded(child: Text('• ${sign.label} : ${sign.advice}', style: theme.textTheme.bodyLarge)),
                          // Fiche d'aide à la décision du signe coché.
                          TextButton.icon(
                            onPressed: () => context.push(decisionAidPath(sign.id)),
                            icon: const Icon(Icons.fact_check_rounded),
                            label: const Text(S.openSheet),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
            Card(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: SwitchListTile(
                title: const Text('Orientée vers un service'),
                value: _referred,
                onChanged: (v) => setState(() => _referred = v),
              ),
            ),
            if (_referred)
              TextField(
                controller: _referredTo,
                decoration: const InputDecoration(labelText: 'Orientée vers (service)'),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: const Text(S.save)),
          ],
        ),
      ),
    );
  }
}
