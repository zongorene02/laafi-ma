import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/security/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/data/media_pickers.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../data/records.dart';

const _kinds = [('prescription', 'Ordonnance'), ('result', 'Résultat d\'examen'), ('other', 'Autre')];

String _kindLabel(Object? kind) => _kinds.firstWhere((k) => k.$1 == kind, orElse: () => _kinds.last).$2;

/// Photos d'ordonnances et de résultats, gardées CHIFFRÉES dans le coffre du
/// profil (jamais dans la galerie du téléphone).
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final pickers = ref.read(mediaPickersProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, size: 32),
              title: const Text(S.takePhoto),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.image_rounded, size: 32),
              title: const Text(S.pickImage),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, size: 32),
              title: const Text(S.pickFile),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    PickedMedia? media;
    try {
      media = choice == 'file' ? await pickers.pickFile() : await pickers.pickImage(camera: choice == 'camera');
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
      return;
    }
    if (media == null || !context.mounted) return;
    final details = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _DocumentDetailsDialog(defaultTitle: media!.name),
    );
    if (details == null) return;
    final blobId = 'doc_${const Uuid().v4()}';
    await ref.read(profileStoreProvider).putBlob(blobId, media.bytes);
    await ref.read(collectionProvider(Col.documents).notifier).save({
      'title': details.$1,
      'kind': details.$2,
      'date': isoDate(DateTime.now()),
      'blob_id': blobId,
      'mime': media.mime,
      'size': media.bytes.length,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(collectionProvider(Col.documents)).valueOrNull ?? const [];
    return LaafiScaffold(
      title: S.documents,
      listenText: 'Vos documents : photos d\'ordonnances ou de résultats. Ils restent fermés à clé sur ce téléphone.',
      backTo: '/carnet',
      scrollable: false,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_doc',
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_a_photo_rounded),
        label: const Text(S.addDocument),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
        children: [
          if (docs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Icon(Icons.photo_library_outlined, size: 72),
            ),
          for (final doc in docs)
            Card(
              child: ListTile(
                onTap: () =>
                    context.push(Uri(path: '/carnet/documents/view', queryParameters: {'id': doc['id']}).toString()),
                leading: CircleAvatar(
                  radius: 24,
                  child: Icon(
                    (doc['mime'] as String? ?? '').startsWith('image/')
                        ? Icons.image_rounded
                        : Icons.picture_as_pdf_rounded,
                  ),
                ),
                title: Text(doc['title']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text('${_kindLabel(doc['kind'])} · ${frDate(doc['date'])}'),
                trailing: ListenButton(
                  text: '${doc['title']}. ${_kindLabel(doc['kind'])}',
                  compact: true,
                  mode: ListenMode.private,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentDetailsDialog extends StatefulWidget {
  const _DocumentDetailsDialog({required this.defaultTitle});

  final String defaultTitle;

  @override
  State<_DocumentDetailsDialog> createState() => _DocumentDetailsDialogState();
}

class _DocumentDetailsDialogState extends State<_DocumentDetailsDialog> {
  late final _title = TextEditingController(text: widget.defaultTitle);
  String _kind = 'prescription';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(S.addDocument),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final kind in _kinds)
                ChoiceChip(
                  label: Text(kind.$2),
                  selected: _kind == kind.$1,
                  onSelected: (_) => setState(() => _kind = kind.$1),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (_title.text.trim().isEmpty ? S.documents : _title.text.trim(), _kind)),
          child: const Text(S.save),
        ),
      ],
    );
  }
}

final _blobProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, id) {
  return ref.watch(profileStoreProvider).getBlob(id);
});

class DocumentViewScreen extends ConsumerWidget {
  const DocumentViewScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = (ref.watch(collectionProvider(Col.documents)).valueOrNull ?? const [])
        .where((d) => d['id'] == id)
        .firstOrNull;
    if (doc == null) {
      return const LaafiScaffold(title: S.documents, body: SizedBox.shrink(), backTo: '/carnet/documents');
    }
    final blob = ref.watch(_blobProvider(doc['blob_id'] as String));
    final isImage = (doc['mime'] as String? ?? '').startsWith('image/');

    return LaafiScaffold(
      title: doc['title']?.toString() ?? S.documents,
      backTo: '/carnet/documents',
      actions: [
        IconButton(
          tooltip: S.delete,
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (!await confirmDialog(context, S.confirmDelete)) return;
            await ref.read(profileStoreProvider).deleteBlob(doc['blob_id'] as String);
            await ref.read(collectionProvider(Col.documents).notifier).remove(id);
            if (context.mounted) context.pop();
          },
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${_kindLabel(doc['kind'])} · ${frDate(doc['date'])}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          blob.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(message: e.toString()),
            data: (bytes) {
              if (bytes == null) return const InfoBanner(text: S.empty);
              if (isImage) {
                return InteractiveViewer(
                  maxScale: 5,
                  child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: Image.memory(bytes)),
                );
              }
              return InfoBanner(
                text: '${S.pdfFile} · ${(bytes.length / 1024).round()} Ko',
                icon: Icons.picture_as_pdf_rounded,
              );
            },
          ),
        ],
      ),
    );
  }
}
