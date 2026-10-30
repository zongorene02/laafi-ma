import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../data/assistant_models.dart';
import '../data/assistant_repository.dart';
import 'assistant_screen.dart';

/// FAQ en cache (consultable hors connexion) ; avec internet, le bouton la
/// met à jour avec les signes de danger.
final cachedFaqProvider = FutureProvider.autoDispose<(FaqBundle, DateTime)?>((ref) {
  return ref.watch(assistantRepositoryProvider).cachedFaq(ref.watch(langProvider));
});

const topicLabels = {
  'grossesse': 'Grossesse',
  'post_partum': 'Après l\'accouchement',
  'contraception': 'Contraception',
  'menstruation': 'Règles',
  'nutrition': 'Alimentation',
  'maladies': 'Maladies',
  'sante_mentale': 'Moral',
  'violences': 'Violences',
  'enfant': 'Enfant',
  'hygiene': 'Hygiène',
  'autre': 'Autre',
};

class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  bool _downloading = false;
  String? _topic;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await ref.read(assistantRepositoryProvider).downloadForOffline(ref.read(langProvider));
      ref.invalidate(cachedFaqProvider);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cached = ref.watch(cachedFaqProvider);
    final lang = ref.watch(langProvider);
    final bundle = cached.valueOrNull;
    final entries = bundle?.$1.entries ?? const <FaqEntry>[];
    final topics = {for (final e in entries) e.topic}.toList()..sort();
    final shown = _topic == null ? entries : entries.where((e) => e.topic == _topic).toList();

    return LaafiScaffold(
      title: S.faq,
      listenText: S.faqListen,
      backTo: '/assistant',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.download_for_offline_rounded, size: 28),
            label: const Text(S.downloadForOffline),
          ),
          if (bundle != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('${S.downloadedOn} ${frDate(bundle.$2.toLocal())}', textAlign: TextAlign.center),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ErrorRetry(message: _error!, onRetry: _download),
          ],
          const SizedBox(height: AppSpacing.md),
          if (topics.length > 1)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('Tout'),
                  selected: _topic == null,
                  onSelected: (_) => setState(() => _topic = null),
                ),
                for (final topic in topics)
                  ChoiceChip(
                    label: Text(topicLabels[topic] ?? topic),
                    selected: _topic == topic,
                    onSelected: (_) => setState(() => _topic = topic),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          if (entries.isEmpty && !cached.isLoading) const InfoBanner(text: S.noFaqOffline),
          for (final entry in shown) FaqTile(entry: entry, lang: lang),
        ],
      ),
    );
  }
}
