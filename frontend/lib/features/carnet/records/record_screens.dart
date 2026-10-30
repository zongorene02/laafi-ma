import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../stats/stats_service.dart';
import '../data/records.dart';
import '../data/reminder_service.dart';
import 'record_spec.dart';
import 'record_specs.dart';

String recordListPath(String specId, {String? parent}) =>
    Uri(path: '/carnet/r/$specId', queryParameters: parent == null ? null : {'parent': parent}).toString();

String recordViewPath(String specId, String id) =>
    Uri(path: '/carnet/r/$specId/view', queryParameters: {'id': id}).toString();

String recordEditPath(String specId, {String? id, String? parent}) =>
    Uri(path: '/carnet/r/$specId/edit', queryParameters: {'id': ?id, 'parent': ?parent}).toString();

/// Liste générique d'une rubrique, avec un en-tête optionnel (estimation du
/// cycle, saisie rapide de l'humeur…).
class RecordListScreen extends ConsumerWidget {
  const RecordListScreen({super.key, required this.specId, this.parentId, this.header, this.protectedArea = false});

  final String specId;
  final String? parentId;
  final Widget? header;
  final bool protectedArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = recordSpecs[specId]!;
    final async = ref.watch(collectionProvider(spec.collection));
    final all = async.valueOrNull ?? const <Map<String, dynamic>>[];
    final records = spec.parentKey == null ? all : all.where((r) => r[spec.parentKey] == parentId).toList();
    final canAdd = spec.maxItems == null || records.length < spec.maxItems!;

    return LaafiScaffold(
      title: spec.title,
      listenText: spec.listenText,
      scrollable: false,
      protectedArea: protectedArea,
      backTo: '/carnet',
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'add_${spec.id}',
              onPressed: () => context.push(recordEditPath(spec.id, parent: parentId)),
              icon: const Icon(Icons.add_rounded, size: 28),
              label: const Text(S.add),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
        children: [
          ?header,
          if (spec.note != null) ...[InfoBanner(text: spec.note!), const SizedBox(height: AppSpacing.sm)],
          if (spec.remindable && kIsWeb) ...[
            const InfoBanner(text: S.webNoReminders, icon: Icons.notifications_off_rounded),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (!canAdd) ...[const InfoBanner(text: S.maxThreeContacts), const SizedBox(height: AppSpacing.sm)],
          if (async.isLoading && all.isEmpty) const Center(child: CircularProgressIndicator()),
          if (!async.isLoading && records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Column(
                children: [
                  Icon(spec.icon, size: 64, color: spec.color.withValues(alpha: 0.5)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(S.empty, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RecordCard(spec: spec, record: record),
            ),
        ],
      ),
    );
  }
}

class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.spec, required this.record, this.onTap});

  final RecordSpec spec;
  final Map<String, dynamic> record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = spec.subtitleOf?.call(record) ?? '';
    return Card(
      child: ListTile(
        onTap: onTap ?? () => context.push(recordViewPath(spec.id, record['id'] as String)),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: spec.color.withValues(alpha: 0.15),
          child: Icon(spec.icon, color: spec.color),
        ),
        title: Text(spec.titleOf(record), style: Theme.of(context).textTheme.titleMedium),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: ListenButton(text: spec.spokenSummary(record), compact: true, mode: ListenMode.private),
      ),
    );
  }
}

/// Fiche d'un élément : chaque champ avec son bouton « Écouter » (voix du
/// téléphone uniquement : ce sont des données personnelles).
class RecordDetailScreen extends ConsumerWidget {
  const RecordDetailScreen({super.key, required this.specId, required this.id, this.footer});

  final String specId;
  final String id;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = recordSpecs[specId]!;
    final records = ref.watch(collectionProvider(spec.collection)).valueOrNull ?? const [];
    final record = records.where((r) => r['id'] == id).firstOrNull;
    final theme = Theme.of(context);

    if (record == null) {
      return LaafiScaffold(title: spec.title, body: const SizedBox.shrink(), backTo: '/carnet');
    }

    Future<void> delete() async {
      if (!await confirmDialog(context, S.confirmDelete)) return;
      await spec.onDeleted?.call(ref, record);
      await ref.read(collectionProvider(spec.collection).notifier).remove(id);
      if (context.mounted) context.pop();
    }

    return LaafiScaffold(
      title: spec.titleOf(record),
      listenText: spec.listenText,
      backTo: '/carnet',
      actions: [
        IconButton(
          tooltip: S.edit,
          icon: const Icon(Icons.edit_rounded),
          onPressed: () => context.push(recordEditPath(spec.id, id: id, parent: record[spec.parentKey] as String?)),
        ),
        IconButton(tooltip: S.delete, icon: const Icon(Icons.delete_outline_rounded), onPressed: delete),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in spec.fields)
            if (field.display(record[field.key]).isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(field.label, style: theme.textTheme.labelLarge),
                            const SizedBox(height: AppSpacing.xs),
                            SelectableText(field.display(record[field.key]), style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                      ListenButton(
                        text: '${field.label} : ${field.display(record[field.key])}',
                        compact: true,
                        mode: ListenMode.private,
                      ),
                    ],
                  ),
                ),
              ),
          ?footer,
        ],
      ),
    );
  }
}

/// Formulaire générique de création / modification.
class RecordFormScreen extends ConsumerStatefulWidget {
  const RecordFormScreen({super.key, required this.specId, this.id, this.parentId, this.initial});

  final String specId;
  final String? id;
  final String? parentId;

  /// Valeurs de départ pour un nouvel élément (ex. date du jour).
  final Map<String, dynamic>? initial;

  @override
  ConsumerState<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends ConsumerState<RecordFormScreen> {
  late final RecordSpec spec = recordSpecs[widget.specId]!;
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};

  /// Version enregistrée avant modification (`null` = nouvel élément).
  Map<String, dynamic>? _before;
  final Map<String, TextEditingController> _controllers = {};
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool _isText(FieldKind kind) => kind == FieldKind.text || kind == FieldKind.multiline || kind == FieldKind.number;

  void _load(List<Map<String, dynamic>> records) {
    if (_loaded) return;
    _loaded = true;
    Map<String, dynamic>? existing;
    if (widget.id != null) {
      existing = records.where((r) => r['id'] == widget.id).firstOrNull;
    } else if (spec.single && records.isNotEmpty) {
      existing = records.first;
    }
    _before = existing == null ? null : Map.of(existing);
    _values.addAll(existing ?? {...?widget.initial, if (spec.parentKey != null) spec.parentKey!: widget.parentId});
    for (final field in spec.fields.where((f) => _isText(f.kind))) {
      _controllers[field.key] = TextEditingController(text: _values[field.key]?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    for (final field in spec.fields) {
      if (field.required && !_isText(field.kind) && (_values[field.key] == null || _values[field.key] == '')) {
        setState(() => _error = '${field.label} : ${S.required.toLowerCase()}');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    for (final field in spec.fields.where((f) => _isText(f.kind))) {
      final text = _controllers[field.key]!.text.trim();
      _values[field.key] = text.isEmpty
          ? null
          : field.kind == FieldKind.number
          ? (num.tryParse(text.replaceAll(',', '.')) ?? text)
          : text;
    }
    final notifier = ref.read(collectionProvider(spec.collection).notifier);
    final id = await notifier.save(_values);
    _values['id'] = id;
    if (spec.remindable && _values['reminder'] == true) {
      await ref.read(reminderServiceProvider).requestPermission();
    }
    await spec.onSaved?.call(ref, _values);
    final event = spec.statEventOf?.call(_before, _values);
    if (event != null) await ref.read(statsServiceProvider).track(event);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(collectionProvider(spec.collection));
    if (!async.hasValue) {
      return LaafiScaffold(
        title: spec.title,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    _load(async.value!);

    return LaafiScaffold(
      title: spec.title,
      listenText: spec.listenText,
      backTo: '/carnet',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final field in spec.fields) ...[_buildField(field), const SizedBox(height: AppSpacing.md)],
            if (_error != null) ...[
              InfoBanner(text: _error!, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: AppSpacing.md),
            ],
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded, size: 28),
              label: const Text(S.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(FieldSpec field) {
    final theme = Theme.of(context);
    switch (field.kind) {
      case FieldKind.text:
      case FieldKind.multiline:
      case FieldKind.number:
        return TextFormField(
          controller: _controllers[field.key],
          minLines: field.kind == FieldKind.multiline ? 3 : 1,
          maxLines: field.kind == FieldKind.multiline ? 8 : 1,
          keyboardType: field.kind == FieldKind.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : (field.key == 'phone' ? TextInputType.phone : TextInputType.text),
          inputFormatters: field.kind == FieldKind.number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
          style: theme.textTheme.titleMedium,
          decoration: InputDecoration(labelText: field.label, hintText: field.hint),
          validator: (value) => field.required && (value == null || value.trim().isEmpty) ? S.required : null,
        );
      case FieldKind.date:
        return _PickerTile(
          label: field.label,
          icon: Icons.calendar_month_rounded,
          value: _values[field.key] == null ? null : frDate(_values[field.key]),
          onClear: field.required ? null : () => setState(() => _values[field.key] = null),
          onTap: () async {
            final initial = parseDate(_values[field.key]) ?? DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1940),
              lastDate: DateTime(DateTime.now().year + 2),
            );
            if (picked != null) setState(() => _values[field.key] = isoDate(picked));
          },
        );
      case FieldKind.time:
        return _PickerTile(
          label: field.label,
          icon: Icons.schedule_rounded,
          value: _values[field.key] as String?,
          onClear: () => setState(() => _values[field.key] = null),
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
            if (picked != null) {
              setState(() => _values[field.key] = hhmm(DateTime(2000, 1, 1, picked.hour, picked.minute)));
            }
          },
        );
      case FieldKind.times:
        final times = [...(_values[field.key] as List? ?? const [])].map((t) => t.toString()).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final time in times)
                  InputChip(
                    label: Text(time, style: theme.textTheme.titleMedium),
                    onDeleted: () => setState(() => _values[field.key] = times.where((t) => t != time).toList()),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_alarm_rounded),
                  label: const Text(S.chooseTime),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 8, minute: 0),
                    );
                    if (picked == null) return;
                    final value = hhmm(DateTime(2000, 1, 1, picked.hour, picked.minute));
                    setState(() => _values[field.key] = ({...times, value}.toList()..sort()));
                  },
                ),
              ],
            ),
          ],
        );
      case FieldKind.choice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final choice in field.choices)
                  ChoiceChip(
                    label: Text(choice.$2, style: theme.textTheme.titleMedium),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    selected: _values[field.key] == choice.$1,
                    onSelected: (selected) => setState(() => _values[field.key] = selected ? choice.$1 : null),
                  ),
              ],
            ),
          ],
        );
      case FieldKind.toggle:
        return Card(
          child: SwitchListTile(
            title: Text(field.label, style: theme.textTheme.titleMedium),
            value: _values[field.key] == true,
            onChanged: (value) => setState(() => _values[field.key] = value),
          ),
        );
    }
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.label, required this.icon, required this.value, required this.onTap, this.onClear});

  final String label;
  final IconData icon;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, size: 30, color: theme.colorScheme.primary),
        title: Text(label, style: theme.textTheme.labelLarge),
        subtitle: Text(value ?? S.chooseDate, style: theme.textTheme.titleMedium),
        trailing: value != null && onClear != null
            ? IconButton(tooltip: S.remove, icon: const Icon(Icons.close_rounded), onPressed: onClear)
            : null,
      ),
    );
  }
}

/// Rubrique à document unique (profil santé) : la fiche si elle existe, le
/// formulaire sinon.
class SingleRecordScreen extends ConsumerWidget {
  const SingleRecordScreen({super.key, required this.specId});

  final String specId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = recordSpecs[specId]!;
    final async = ref.watch(collectionProvider(spec.collection));
    return async.when(
      loading: () => LaafiScaffold(
        title: spec.title,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => LaafiScaffold(
        title: spec.title,
        body: ErrorRetry(message: e.toString()),
      ),
      data: (records) => records.isEmpty
          ? RecordFormScreen(specId: specId)
          : RecordDetailScreen(specId: specId, id: records.first['id'] as String),
    );
  }
}

/// Pied de la fiche d'un enfant : accès à ses vaccins.
class ChildVaccinesButton extends StatelessWidget {
  const ChildVaccinesButton({super.key, required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: FilledButton.icon(
        onPressed: () => context.push(recordListPath(Col.vaccines, parent: childId)),
        icon: const Icon(Icons.vaccines_rounded, size: 28),
        label: const Text(S.vaccines),
      ),
    );
  }
}
