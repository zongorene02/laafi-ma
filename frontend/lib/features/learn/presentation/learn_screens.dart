import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/audio_playback_service.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../../shared/widgets/provisional_note.dart';
import '../../carnet/data/records.dart';
import '../../help/presentation/help_gate.dart';
import '../../stats/stats_service.dart';
import '../data/learn_repository.dart';
import '../domain/weekly_tip.dart';

/// Liste des capsules (par parcours), avec téléchargement pour hors connexion.
class LearnHomeScreen extends ConsumerStatefulWidget {
  const LearnHomeScreen({super.key, this.track, this.protectedArea = false});

  final String? track;

  /// « Mes droits », ouvert depuis la page Aide : même protection qu'elle.
  final bool protectedArea;

  @override
  ConsumerState<LearnHomeScreen> createState() => _LearnHomeScreenState();
}

class _LearnHomeScreenState extends ConsumerState<LearnHomeScreen> {
  late String? _track = widget.track;
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final audio = await ref.read(learnRepositoryProvider).downloadForOffline(ref.read(langProvider));
      if (mounted) {
        showSnack(
          context,
          kIsWeb ? 'Leçons gardées (texte seulement sur navigateur).' : 'Leçons gardées ($audio fichiers audio).',
        );
      }
      ref.invalidate(capsulesProvider);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(capsulesProvider);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final title = widget.track == 'droits' ? S.rights : S.learnTitle;
    // Moins de 18 ans (profil santé) : le parcours « Adolescente » d'abord.
    final minor = ref.watch(isMinorProvider).valueOrNull ?? false;

    final page = LaafiScaffold(
      title: title,
      listenText: S.learnListen,
      protectedArea: widget.protectedArea,
      backTo: widget.protectedArea ? '/help' : '/home',
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
          const SizedBox(height: AppSpacing.md),
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(message: e.toString(), onRetry: () => ref.invalidate(capsulesProvider)),
            data: (data) {
              final (capsules, fromCache) = data;
              final tracks = {for (final c in capsules) c.track}.toList()
                ..sort((a, b) => S.tracks.keys.toList().indexOf(a).compareTo(S.tracks.keys.toList().indexOf(b)));
              final shown = _track == null
                  ? orderForAge(capsules, minor: minor)
                  : capsules.where((c) => c.track == _track).toList();
              final suggestTeen = minor && widget.track == null && _track == null && tracks.contains(minorTrack);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fromCache) ...[
                    const InfoBanner(text: '${S.offline} · ${S.offlineData}', icon: Icons.wifi_off_rounded),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (suggestTeen) ...[
                    Card(
                      color: AppTheme.plum.withValues(alpha: 0.08),
                      child: ListTile(
                        leading: const Icon(Icons.star_rounded, color: AppTheme.plum, size: 32),
                        title: const Text(S.suggestedForYou),
                        subtitle: Text(S.tracks[minorTrack]!, style: theme.textTheme.titleMedium),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => setState(() => _track = minorTrack),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (widget.track == null && tracks.length > 1)
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        ChoiceChip(
                          label: const Text('Tout'),
                          selected: _track == null,
                          onSelected: (_) => setState(() => _track = null),
                        ),
                        for (final t in tracks)
                          ChoiceChip(
                            label: Text(S.tracks[t] ?? t),
                            selected: _track == t,
                            onSelected: (_) => setState(() => _track = t),
                          ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.md),
                  if (shown.isEmpty) const InfoBanner(text: S.empty),
                  if (shown.any((c) => c.provisional)) ...[
                    const ProvisionalNote(),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  for (final capsule in shown)
                    Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.sky.withValues(alpha: 0.15),
                          child: const Icon(Icons.headphones_rounded, color: AppTheme.sky),
                        ),
                        title: Text(capsule.textIn(lang).title, style: theme.textTheme.titleMedium),
                        subtitle: Text(S.tracks[capsule.track] ?? capsule.track),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/learn/capsule/${capsule.id}'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
    return widget.protectedArea ? HelpGate(child: page) : page;
  }
}

class CapsuleScreen extends ConsumerStatefulWidget {
  const CapsuleScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<CapsuleScreen> createState() => _CapsuleScreenState();
}

class _CapsuleScreenState extends ConsumerState<CapsuleScreen> {
  final Map<int, int> _answers = {};

  Future<void> _play(String url) async {
    final player = ref.read(audioPlaybackServiceProvider);
    try {
      final cached = await ref.read(learnRepositoryProvider).cachedAudio(url);
      if (cached != null) {
        final lower = url.toLowerCase();
        await player.play(
          cached,
          mimeType: lower.endsWith('.mp3') ? 'audio/mpeg' : (lower.endsWith('.ogg') ? 'audio/ogg' : 'audio/wav'),
        );
      } else {
        await player.playUrl(ApiClient.mediaUrl(url));
      }
      await ref.read(statsServiceProvider).track(StatEvent.capsulePlayed);
    } catch (_) {
      if (mounted) showSnack(context, S.listenUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final capsules = ref.watch(capsulesProvider).valueOrNull?.$1 ?? const <Capsule>[];
    final capsule = capsules.where((c) => c.id == widget.id).firstOrNull;
    if (capsule == null) {
      return const LaafiScaffold(
        title: S.learnTitle,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final text = capsule.textIn(lang);
    final shownLang = capsule.langShown(lang);

    return LaafiScaffold(
      title: text.title,
      backTo: '/learn',
      protectedArea: capsule.track == 'droits',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text.title, style: theme.textTheme.headlineSmall),
          if (capsule.provisional) ...[const SizedBox(height: AppSpacing.sm), const ProvisionalNote()],
          const SizedBox(height: AppSpacing.md),
          if (text.audioUrl != null)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _play(text.audioUrl!),
                  icon: const Icon(Icons.play_arrow_rounded, size: 32),
                  label: const Text(S.play),
                ),
                IconButton.filledTonal(
                  tooltip: S.stop,
                  onPressed: () => ref.read(audioPlaybackServiceProvider).stop(),
                  icon: const Icon(Icons.stop_rounded),
                ),
                Chip(
                  avatar: Icon(text.isSynthetic ? Icons.smart_toy_rounded : Icons.person_rounded, size: 18),
                  label: Text(text.isSynthetic ? S.synthVoice : S.humanVoice),
                ),
                if (capsule.provisional)
                  const ListenButton(
                    text: S.provisionalNote,
                    compact: true,
                    mode: ListenMode.content,
                    contentLang: 'fr',
                  ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: ListenButton(
                text: withProvisionalNote(text.text, provisional: capsule.provisional),
                mode: ListenMode.content,
                contentLang: shownLang,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SelectableText(text.text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: 18)),
          if (capsule.license != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Licence : ${capsule.license}', style: theme.textTheme.bodySmall),
          ],
          if (capsule.quiz.isNotEmpty) ...[
            const SectionTitle(S.quiz),
            for (final (qi, item) in capsule.quiz.indexed)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(item.questionIn(lang), style: theme.textTheme.titleMedium)),
                          ListenButton(
                            text: item.questionIn(lang),
                            compact: true,
                            mode: ListenMode.content,
                            contentLang: item.question.containsKey(lang) ? lang : 'fr',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (var ci = 0; ci < item.choices.length; ci++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              backgroundColor: _answers[qi] == null
                                  ? null
                                  : ci == item.correctIndex
                                  ? AppTheme.leaf.withValues(alpha: 0.18)
                                  : (_answers[qi] == ci ? AppTheme.amber.withValues(alpha: 0.2) : null),
                            ),
                            onPressed: () => setState(() => _answers[qi] = ci),
                            child: Text(item.choiceIn(ci, lang)),
                          ),
                        ),
                      if (_answers[qi] != null)
                        Text(
                          _answers[qi] == item.correctIndex
                              ? S.goodAnswer
                              : S.rightAnswerIs(item.choiceIn(item.correctIndex, lang)),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: _answers[qi] == item.correctIndex ? AppTheme.leaf : theme.colorScheme.onSurface,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
