import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/security/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/data/audio_playback_service.dart';
import '../../../shared/data/media_pickers.dart';
import '../../../shared/data/pcm_recorder.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../carnet/data/records.dart';
import 'help_gate.dart';

/// Journal privé : pages datées (texte, photos, notes vocales), chiffrées
/// dans le coffre du profil. Aucune notification, aucune trace ailleurs.
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(collectionProvider(Col.journal)).valueOrNull ?? const [];
    final theme = Theme.of(context);
    return HelpGate(
      child: LaafiScaffold(
        title: S.journal,
        listenText: S.journalListen,
        protectedArea: true,
        backTo: '/help',
        scrollable: false,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'journal_add',
          onPressed: () => context.push('/help/journal/edit'),
          icon: const Icon(Icons.edit_rounded),
          label: const Text(S.newEntry),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
          children: [
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Icon(Icons.menu_book_outlined, size: 72),
              ),
            for (final entry in entries)
              Card(
                child: ListTile(
                  onTap: () =>
                      context.push(Uri(path: '/help/journal/edit', queryParameters: {'id': entry['id']}).toString()),
                  title: Text(_title(entry), style: theme.textTheme.titleMedium),
                  subtitle: Text(
                    [
                      frDate(entry['date']),
                      if ((entry['photos'] as List? ?? const []).isNotEmpty) '📷 ${(entry['photos'] as List).length}',
                      if ((entry['audios'] as List? ?? const []).isNotEmpty) '🎙 ${(entry['audios'] as List).length}',
                    ].join(' · '),
                  ),
                  trailing: ListenButton(
                    text: entry['text']?.toString() ?? '',
                    compact: true,
                    mode: ListenMode.private,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _title(Map<String, dynamic> entry) {
    final text = (entry['text'] as String? ?? '').trim();
    if (text.isEmpty) return frDate(entry['date']);
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }
}

final _journalBlobProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, id) {
  return ref.watch(profileStoreProvider).getBlob(id);
});

class JournalEntryScreen extends ConsumerStatefulWidget {
  const JournalEntryScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends ConsumerState<JournalEntryScreen> {
  final _text = TextEditingController();
  final _recorder = PcmRecorder();
  List<String> _photos = [];
  List<String> _audios = [];
  String _date = isoDate(DateTime.now());
  bool _loaded = false;
  bool _recording = false;

  @override
  void dispose() {
    _text.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _load(List<Map<String, dynamic>> entries) {
    if (_loaded) return;
    _loaded = true;
    final entry = entries.where((e) => e['id'] == widget.id).firstOrNull;
    if (entry == null) return;
    _text.text = entry['text'] as String? ?? '';
    _photos = [...(entry['photos'] as List? ?? const []).map((e) => e.toString())];
    _audios = [...(entry['audios'] as List? ?? const []).map((e) => e.toString())];
    _date = entry['date'] as String? ?? _date;
  }

  Future<void> _addPhoto() async {
    final media = await ref.read(mediaPickersProvider).pickImage(camera: false);
    if (media == null) return;
    final id = 'journal_${const Uuid().v4()}';
    await ref.read(profileStoreProvider).putBlob(id, media.bytes);
    setState(() => _photos = [..._photos, id]);
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final wav = await _recorder.stop();
      setState(() => _recording = false);
      if (wav == null) return;
      final id = 'journal_${const Uuid().v4()}';
      await ref.read(profileStoreProvider).putBlob(id, wav);
      setState(() => _audios = [..._audios, id]);
    } else {
      final ok = await _recorder.start();
      if (!ok) {
        if (mounted) showSnack(context, S.micDenied);
        return;
      }
      setState(() => _recording = true);
    }
  }

  Future<void> _save() async {
    if (_recording) await _toggleRecording();
    await ref.read(collectionProvider(Col.journal).notifier).save({
      'id': ?widget.id,
      'date': _date,
      'text': _text.text,
      'photos': _photos,
      'audios': _audios,
    });
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, S.confirmDelete)) return;
    final store = ref.read(profileStoreProvider);
    for (final id in [..._photos, ..._audios]) {
      await store.deleteBlob(id);
    }
    if (widget.id != null) await ref.read(collectionProvider(Col.journal).notifier).remove(widget.id!);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(collectionProvider(Col.journal));
    if (!entries.hasValue) {
      return const HelpGate(
        child: LaafiScaffold(
          title: S.journal,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    _load(entries.value!);
    final theme = Theme.of(context);

    return HelpGate(
      child: LaafiScaffold(
        title: frDate(_date),
        listenText: S.journalListen,
        protectedArea: true,
        backTo: '/help/journal',
        actions: [
          if (widget.id != null)
            IconButton(tooltip: S.delete, icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 20,
              style: theme.textTheme.titleMedium,
              decoration: const InputDecoration(hintText: S.writeHere),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _recording ? null : _addPhoto,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text(S.addPhoto),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: _recording
                        ? FilledButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white)
                        : null,
                    onPressed: _toggleRecording,
                    icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                    label: Text(_recording ? S.stop : S.recordAudio),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (index, id) in _audios.indexed)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: Text('${S.recordAudio} ${index + 1}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: S.play,
                        icon: const Icon(Icons.play_arrow_rounded, size: 30),
                        onPressed: () async {
                          final bytes = await ref.read(profileStoreProvider).getBlob(id);
                          if (bytes != null) await ref.read(audioPlaybackServiceProvider).play(bytes);
                        },
                      ),
                      IconButton(
                        tooltip: S.remove,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () async {
                          await ref.read(profileStoreProvider).deleteBlob(id);
                          setState(() => _audios = _audios.where((a) => a != id).toList());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final id in _photos)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(
                          width: 140,
                          height: 140,
                          child: Consumer(
                            builder: (context, ref, _) {
                              final bytes = ref.watch(_journalBlobProvider(id)).valueOrNull;
                              return bytes == null
                                  ? const ColoredBox(color: Colors.black12)
                                  : Image.memory(bytes, fit: BoxFit.cover);
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton.filledTonal(
                          tooltip: S.remove,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () async {
                            await ref.read(profileStoreProvider).deleteBlob(id);
                            setState(() => _photos = _photos.where((p) => p != id).toList());
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: const Text(S.save)),
          ],
        ),
      ),
    );
  }
}
