import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/security/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../data/records.dart';
import '../domain/share_log.dart';
import '../domain/share_payload.dart';

/// « Montrer à un soignant » : la femme choisit les rubriques, un QR code
/// valable 15 minutes s'affiche. Rien ne passe par internet.
class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  final Set<String> _sections = {'p'};
  SharePayload? _payload;
  String? _encoded;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    final dump = await ref.read(profileStoreProvider).dump();
    final payload = SharePayload.create(buildShareData(dump, _sections));
    // Journal des partages (coffre du profil) : date, rubriques, expiration.
    await ref
        .read(collectionProvider(Col.shareLog).notifier)
        .save(shareLogEntry(payload, _sections, id: const Uuid().v4()));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_payload?.isExpired(DateTime.now()) ?? false) _ticker?.cancel();
    });
    setState(() {
      _payload = payload;
      _encoded = payload.encode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = _payload;
    final expired = payload?.isExpired(DateTime.now()) ?? false;
    final remaining = payload == null ? Duration.zero : payload.expiresAt.difference(DateTime.now().toUtc());

    return LaafiScaffold(
      title: S.share,
      listenText: S.shareListen,
      backTo: '/carnet',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (payload == null || expired) ...[
            Text(S.chooseSections, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            for (final entry in shareSections.entries)
              Card(
                child: CheckboxListTile(
                  value: _sections.contains(entry.key),
                  title: Text(entry.value, style: theme.textTheme.titleMedium),
                  onChanged: (checked) => setState(() {
                    checked == true ? _sections.add(entry.key) : _sections.remove(entry.key);
                  }),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            if (expired) ...[const InfoBanner(text: S.qrExpired), const SizedBox(height: AppSpacing.sm)],
            FilledButton.icon(
              onPressed: _sections.isEmpty ? null : _generate,
              icon: const Icon(Icons.qr_code_2_rounded, size: 28),
              label: const Text(S.showQr),
            ),
          ] else ...[
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: QrImageView(
                  data: _encoded!,
                  size: 300,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            BigValueCard(
              label: S.validUntil(hhmm(payload.expiresAt.toLocal())),
              value: '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
              note: '${S.generatedAt} ${hhmm(payload.generatedAt.toLocal())}',
            ),
            if (_encoded!.length > SharePayload.maxLength) ...[
              const SizedBox(height: AppSpacing.sm),
              const InfoBanner(
                text: 'Beaucoup d\'informations : le code est très dense. Enlevez une rubrique si le soignant n\'arrive pas à le lire.',
                icon: Icons.warning_amber_rounded,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _payload = null;
                _encoded = null;
                _ticker?.cancel();
              }),
              icon: const Icon(Icons.close_rounded),
              label: const Text(S.close),
            ),
          ],
          const _ShareLog(),
        ],
      ),
    );
  }
}

/// « Journal des partages » : chaque code créé, effaçable un par un.
class _ShareLog extends ConsumerWidget {
  const _ShareLog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(collectionProvider(Col.shareLog)).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(S.shareLog),
        Row(
          children: [
            Expanded(child: Text(S.shareLogNote, style: theme.textTheme.bodyMedium)),
            const ListenButton(text: S.shareLogNote, compact: true),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (entries.isEmpty) const InfoBanner(text: S.shareLogEmpty),
        for (final entry in entries)
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              title: Text(shareLogSummary(entry)),
              trailing: IconButton(
                tooltip: S.delete,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (!await confirmDialog(context, S.confirmDelete)) return;
                  await ref.read(collectionProvider(Col.shareLog).notifier).remove(entry['id'] as String);
                },
              ),
            ),
          ),
      ],
    );
  }
}
