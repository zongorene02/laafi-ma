import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../data/agent_repository.dart';
import '../data/sync_merge.dart';
import 'agent_gate.dart';
import 'agent_providers.dart';

const ageRanges = ['<15', '15-19', '20-24', '25-34', '35-49', '50+'];

const visitTypes = {
  'prenatal': 'Prénatale',
  'postnatal': 'Postnatale',
  'child': 'Enfant',
  'family_planning': 'Planification familiale',
  'follow_up': 'Suivi',
  'other': 'Autre',
};

class BeneficiariesScreen extends ConsumerWidget {
  const BeneficiariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(agentListProvider(AgentCollections.beneficiaries));
    return AgentGate(
      child: LaafiScaffold(
        title: S.beneficiaries,
        listenText: 'Vos bénéficiaires. Un pseudonyme seulement, avec son accord.',
        backTo: '/agent',
        scrollable: false,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'add_beneficiary',
          onPressed: () => context.push('/agent/beneficiary/edit'),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text(S.add),
        ),
        body: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(message: e.toString()),
          data: (records) => ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
            children: [
              if (records.isEmpty) const InfoBanner(text: S.empty),
              for (final b in records)
                Card(
                  child: ListTile(
                    onTap: () =>
                        context.push(Uri(path: '/agent/beneficiary/view', queryParameters: {'id': b['id']}).toString()),
                    leading: CircleAvatar(
                      child: Icon(b['pregnant'] == true ? Icons.pregnant_woman_rounded : Icons.person_rounded),
                    ),
                    title: Text(b['pseudonym']?.toString() ?? ''),
                    subtitle: Text([b['age_range'], b['village']].whereType<String>().join(' · ')),
                    trailing: b[dirtyFlag] == true ? const Icon(Icons.cloud_upload_outlined) : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BeneficiaryFormScreen extends ConsumerStatefulWidget {
  const BeneficiaryFormScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<BeneficiaryFormScreen> createState() => _BeneficiaryFormScreenState();
}

class _BeneficiaryFormScreenState extends ConsumerState<BeneficiaryFormScreen> {
  final _pseudonym = TextEditingController();
  final _village = TextEditingController();
  final _notes = TextEditingController();

  /// Numéro gardé SEULEMENT sur ce téléphone (jamais dans la synchro).
  final _phone = TextEditingController();
  Map<String, dynamic>? _existing;
  String? _nextDate;
  String? _nextReason;
  String? _ageRange;
  bool _pregnant = false;
  String? _dueDate;
  int _children = 0;
  bool _consent = false;
  bool _loaded = false;
  String? _error;

  @override
  void dispose() {
    _pseudonym.dispose();
    _village.dispose();
    _notes.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _load(List<Map<String, dynamic>> records) {
    if (_loaded) return;
    _loaded = true;
    final b = records.where((r) => r['id'] == widget.id).firstOrNull;
    if (b == null) return;
    _existing = b;
    _pseudonym.text = b['pseudonym'] as String? ?? '';
    _village.text = b['village'] as String? ?? '';
    _notes.text = b['notes'] as String? ?? '';
    _ageRange = b['age_range'] as String?;
    _pregnant = b['pregnant'] == true;
    _dueDate = b['expected_due_date'] as String?;
    _children = (b['children_under_5'] as num?)?.toInt() ?? 0;
    _consent = b['consent_given_at'] != null;
    _nextDate = b['next_appointment_date'] as String?;
    _nextReason = b['next_appointment_reason'] as String?;
    ref.read(agentRepositoryProvider.future).then((repo) => repo.phoneOf(b['id'] as String)).then((phone) {
      if (mounted && phone != null && _phone.text.isEmpty) _phone.text = phone;
    });
  }

  Future<void> _save() async {
    if (_pseudonym.text.trim().isEmpty || _ageRange == null) {
      setState(() => _error = 'Pseudonyme et tranche d\'âge : ${S.required.toLowerCase()}.');
      return;
    }
    if (!_consent) {
      setState(() => _error = S.consentRequired);
      return;
    }
    final repo = await ref.read(agentRepositoryProvider.future);
    String? blank(String text) => text.trim().isEmpty ? null : text.trim();
    final id = _existing?['id'] as String? ?? const Uuid().v4();
    await repo.save(AgentCollections.beneficiaries, {
      'id': id,
      'pseudonym': _pseudonym.text.trim(),
      'village': blank(_village.text),
      'age_range': _ageRange,
      'pregnant': _pregnant,
      'expected_due_date': _pregnant ? _dueDate : null,
      'children_under_5': _children,
      'next_appointment_date': _nextDate,
      'next_appointment_reason': _nextDate == null ? null : _nextReason,
      'consent_given_at': _existing?['consent_given_at'] ?? utcTimestamp(DateTime.now()),
      'notes': blank(_notes.text),
      'deleted': false,
    });
    await repo.setPhone(id, _phone.text);
    refreshAgentLists(ref);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(agentListProvider(AgentCollections.beneficiaries));
    if (!list.hasValue) {
      return const AgentGate(
        child: LaafiScaffold(
          title: S.beneficiaries,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    _load(list.value!);
    final theme = Theme.of(context);

    return AgentGate(
      child: LaafiScaffold(
        title: S.beneficiaries,
        backTo: '/agent/beneficiaries',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pseudonym,
              decoration: const InputDecoration(labelText: 'Pseudonyme (pas le vrai nom)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _village,
              decoration: const InputDecoration(labelText: 'Village / quartier'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Tranche d\'âge', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final range in ageRanges)
                  ChoiceChip(
                    label: Text(range),
                    selected: _ageRange == range,
                    onSelected: (_) => setState(() => _ageRange = range),
                  ),
              ],
            ),
            Card(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: SwitchListTile(
                title: const Text('Enceinte'),
                value: _pregnant,
                onChanged: (v) => setState(() => _pregnant = v),
              ),
            ),
            if (_pregnant)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('Date prévue d\'accouchement'),
                  subtitle: Text(_dueDate == null ? S.chooseDate : frDate(_dueDate)),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: parseDate(_dueDate) ?? now,
                      firstDate: now.subtract(const Duration(days: 60)),
                      lastDate: now.add(const Duration(days: 300)),
                    );
                    if (picked != null) setState(() => _dueDate = isoDate(picked));
                  },
                ),
              ),
            Card(
              child: ListTile(
                title: const Text('Enfants de moins de 5 ans'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _children > 0 ? () => setState(() => _children--) : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    Text('$_children', style: theme.textTheme.titleLarge),
                    IconButton(
                      onPressed: () => setState(() => _children++),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              child: ListTile(
                leading: const Icon(Icons.event_available_rounded),
                title: const Text(S.nextAppointment),
                subtitle: Text(_nextDate == null ? S.chooseDate : frDate(_nextDate)),
                trailing: _nextDate == null
                    ? null
                    : IconButton(
                        tooltip: S.clearDate,
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _nextDate = null),
                      ),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: parseDate(_nextDate) ?? now,
                    firstDate: now.subtract(const Duration(days: 60)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _nextDate = isoDate(picked));
                },
              ),
            ),
            if (_nextDate != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(S.nextAppointmentReason, style: theme.textTheme.titleSmall),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final entry in S.appointmentReasons.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _nextReason == entry.key,
                      onSelected: (_) => setState(() => _nextReason = entry.key),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: S.phoneLocalOnly,
                helperText: S.phoneLocalOnlyNote,
                helperMaxLines: 2,
                prefixIcon: Icon(Icons.phone_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            Card(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              color: _consent ? null : AppTheme.amber.withValues(alpha: 0.15),
              child: CheckboxListTile(
                value: _consent,
                // Un consentement déjà donné ne se décoche pas : on supprime la
                // fiche si la personne retire son accord.
                onChanged: _existing?['consent_given_at'] != null ? null : (v) => setState(() => _consent = v ?? false),
                title: const Text(S.consentCheckbox),
              ),
            ),
            if (_error != null) ...[
              InfoBanner(text: _error!, color: theme.colorScheme.error),
              const SizedBox(height: AppSpacing.sm),
            ],
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: const Text(S.save)),
          ],
        ),
      ),
    );
  }
}

class BeneficiaryDetailScreen extends ConsumerWidget {
  const BeneficiaryDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beneficiaries = ref.watch(agentListProvider(AgentCollections.beneficiaries)).valueOrNull ?? const [];
    final visits = ref.watch(agentListProvider(AgentCollections.visits)).valueOrNull ?? const [];
    final phone = ref.watch(agentPhonesProvider).valueOrNull?[id];
    final b = beneficiaries.where((r) => r['id'] == id).firstOrNull;
    final theme = Theme.of(context);
    if (b == null) {
      return const AgentGate(
        child: LaafiScaffold(title: S.beneficiaries, body: SizedBox.shrink(), backTo: '/agent/beneficiaries'),
      );
    }
    final mine = visits.where((v) => v['beneficiary_id'] == id).toList();

    return AgentGate(
      child: LaafiScaffold(
        title: b['pseudonym']?.toString() ?? '',
        backTo: '/agent/beneficiaries',
        actions: [
          IconButton(
            tooltip: S.edit,
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push(Uri(path: '/agent/beneficiary/edit', queryParameters: {'id': id}).toString()),
          ),
          IconButton(
            tooltip: S.delete,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              if (!await confirmDialog(context, S.confirmDelete)) return;
              final repo = await ref.read(agentRepositoryProvider.future);
              await repo.softDelete(AgentCollections.beneficiaries, b);
              refreshAgentLists(ref);
              if (context.mounted) context.pop();
            },
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                b['age_range'],
                b['village'],
                if (b['pregnant'] == true)
                  'Enceinte${b['expected_due_date'] == null ? '' : ' · DPA ${frDate(b['expected_due_date'])}'}',
                'Enfants < 5 ans : ${b['children_under_5'] ?? 0}',
              ].whereType<String>().join(' · '),
              style: theme.textTheme.titleMedium,
            ),
            if (b['next_appointment_date'] != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  '${S.nextAppointment} : ${frDate(b['next_appointment_date'])}',
                  ?S.appointmentReasons[b['next_appointment_reason']],
                ].join(' · '),
                style: theme.textTheme.titleMedium,
              ),
            ],
            if (phone != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('${S.contactPhone} : $phone', style: theme.textTheme.bodyLarge),
            ],
            if (b['notes'] != null) ...[const SizedBox(height: AppSpacing.sm), Text(b['notes'].toString())],
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () =>
                  context.push(Uri(path: '/agent/visit/edit', queryParameters: {'beneficiary': id}).toString()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nouvelle visite'),
            ),
            const SectionTitle(S.visits, listen: false),
            if (mine.isEmpty) const InfoBanner(text: S.empty),
            for (final v in mine)
              Card(
                child: ListTile(
                  onTap: () => context.push(
                    Uri(path: '/agent/visit/edit', queryParameters: {'beneficiary': id, 'id': v['id']}).toString(),
                  ),
                  leading: Icon(
                    (v['danger_sign_ids'] as List? ?? const []).isNotEmpty
                        ? Icons.warning_amber_rounded
                        : Icons.event_note_rounded,
                    color: (v['danger_sign_ids'] as List? ?? const []).isNotEmpty ? AppTheme.danger : null,
                  ),
                  title: Text('${visitTypes[v['type']] ?? v['type']} · ${frDate(v['visit_date'])}'),
                  subtitle: v['referred'] == true ? Text('Orientée vers : ${v['referred_to'] ?? '—'}') : null,
                  trailing: v[dirtyFlag] == true ? const Icon(Icons.cloud_upload_outlined) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
