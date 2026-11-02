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
import '../../translate_voice/presentation/widgets/pulsing_mic_button.dart';
import '../data/assistant_models.dart';
import 'assistant_controller.dart';
import 'danger_banner.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _text = TextEditingController();
  bool _showText = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    FocusScope.of(context).unfocus();
    await ref.read(assistantControllerProvider.notifier).askText(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    // Phrase d'aide secrète reconnue : on efface tout et on ouvre la page Aide
    // (qui demande son code s'il existe), sans aucun message.
    ref.listen(assistantControllerProvider.select((s) => s.openHelp), (_, open) {
      if (!open) return;
      _text.clear();
      setState(() => _showText = false);
      ref.read(assistantControllerProvider.notifier).reset();
      context.go('/help');
    });
    final state = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final recording = state.status == AssistantStatus.recording;
    final sending = state.status == AssistantStatus.sending;
    final confirming = state.status == AssistantStatus.confirming;

    return LaafiScaffold(
      title: S.assistantTitle,
      listenText: S.assistantListen,
      actions: [
        IconButton(
          tooltip: S.faq,
          iconSize: 28,
          icon: const Icon(Icons.quiz_rounded),
          onPressed: () => context.push('/assistant/faq'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Transform.scale(
              scale: 1.4,
              child: PulsingMicButton(
                isActive: recording,
                isConnecting: sending,
                // Pendant la confirmation, toucher le micro = « je répète ».
                onTap: recording ? controller.stopAndSend : controller.startRecording,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            recording ? S.tapToSend : (sending ? S.sending : S.tapToSpeak),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          if (!_showText)
            OutlinedButton.icon(
              onPressed: sending || recording || confirming ? null : () => setState(() => _showText = true),
              icon: const Icon(Icons.keyboard_rounded),
              label: const Text(S.typeQuestion),
            )
          else ...[
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 5,
              style: theme.textTheme.titleMedium,
              decoration: const InputDecoration(hintText: S.typeQuestion),
              onSubmitted: (_) => _ask(),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: sending ? null : _ask,
              icon: const Icon(Icons.send_rounded),
              label: const Text(S.ask),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (state.error != null) ErrorRetry(message: state.error!),
          if (confirming && state.transcript != null)
            _ConfirmCard(
              transcript: state.transcript!,
              lang: lang,
              onYes: controller.confirmTranscript,
              onNo: controller.rejectTranscript,
            ),
          if (state.answer != null) _AnswerView(state: state, answer: state.answer!, lang: lang),
          if (state.status == AssistantStatus.offline) _OfflineView(state: state, lang: lang),
        ],
      ),
    );
  }
}

/// « Vous avez demandé : … ? » avec deux gros boutons Oui / Non.
class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.transcript, required this.lang, required this.onYes, required this.onNo});

  final String transcript;
  final String lang;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded, size: 32),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(S.confirmQuestion(transcript), style: theme.textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                const ListenButton(text: S.confirmListen),
                ListenButton(text: transcript, compact: true, mode: ListenMode.content, contentLang: lang),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              onPressed: onYes,
              icon: const Icon(Icons.check_rounded, size: 32),
              label: const Text(S.yes, style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              onPressed: onNo,
              icon: const Icon(Icons.mic_rounded, size: 32),
              label: const Text(S.confirmRepeat, style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerView extends ConsumerWidget {
  const _AnswerView({required this.state, required this.answer, required this.lang});

  final AssistantState state;
  final AssistantAnswer answer;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entry = answer.entry;
    final heard = answer.transcript ?? (state.voice ? state.question : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (answer.danger && answer.dangerSigns.isNotEmpty) ...[
          DangerBanner(signs: answer.dangerSigns, contentLang: lang),
          const SizedBox(height: AppSpacing.md),
        ],
        if (heard != null && heard.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.record_voice_over_rounded),
              title: const Text(S.youSaid),
              subtitle: Text(heard, style: theme.textTheme.titleMedium),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (entry != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(entry.question, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(entry.answer, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                  if (entry.provisional) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ProvisionalNote(source: entry.source),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AudioAnswerRow(
                    audioUrl: entry.audioUrl,
                    audioKind: entry.audioKind,
                    text: entry.answer,
                    lang: lang,
                    provisional: entry.provisional,
                  ),
                ],
              ),
            ),
          )
        else
          InfoBanner(
            text: answer.fallbackMessage ?? S.offlineAnswerNote,
            icon: Icons.support_agent_rounded,
            child: ListenButton(
              text: answer.fallbackMessage ?? S.offlineAnswerNote,
              mode: answer.fallbackMessage == null ? ListenMode.interface : ListenMode.content,
              contentLang: lang,
            ),
          ),
        if (entry != null) ...[
          const SizedBox(height: AppSpacing.md),
          _UnderstoodCard(state: state, entry: entry, lang: lang),
        ],
      ],
    );
  }
}

/// « Avez-vous compris ? » après une réponse : une seule réponse comptée
/// (statistique anonyme). Sur « Non » : réécouter, et l'idée de demander à
/// l'agent de santé (aucun contenu de santé ajouté ici).
class _UnderstoodCard extends ConsumerWidget {
  const _UnderstoodCard({required this.state, required this.entry, required this.lang});

  final AssistantState state;
  final AnswerEntry entry;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(assistantControllerProvider.notifier);
    final understood = state.understood;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(S.understoodQuestion, style: theme.textTheme.titleLarge)),
                const ListenButton(text: S.understoodQuestion, compact: true),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (understood == null)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                      onPressed: () => controller.markUnderstood(true),
                      icon: const Icon(Icons.thumb_up_alt_rounded, size: 28),
                      label: const Text(S.yes, style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                      onPressed: () => controller.markUnderstood(false),
                      icon: const Icon(Icons.help_outline_rounded, size: 28),
                      label: const Text(S.no, style: TextStyle(fontSize: 22)),
                    ),
                  ),
                ],
              )
            else if (understood)
              const Text(S.understoodThanks)
            else ...[
              Row(
                children: [
                  Expanded(child: Text(S.notUnderstoodHint, style: theme.textTheme.bodyLarge)),
                  const ListenButton(text: S.notUnderstoodHint, compact: true),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (entry.audioUrl != null)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: controller.replayAnswer,
                  icon: const Icon(Icons.replay_rounded, size: 28),
                  label: const Text(S.replayAnswer),
                )
              else
                ListenButton(
                  text: withProvisionalNote(entry.answer, provisional: entry.provisional),
                  mode: ListenMode.content,
                  contentLang: spokenLang(lang, provisional: entry.provisional),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lecture de la réponse : enregistrement servi par l'API (avec la mention
/// « voix de synthèse » quand c'en est une), ou synthèse à la demande. Une
/// réponse [provisional] dit aussi sa mention : dans le texte lu, ou par un
/// bouton à part quand l'audio vient du serveur.
class AudioAnswerRow extends ConsumerWidget {
  const AudioAnswerRow({
    super.key,
    this.audioUrl,
    this.audioKind,
    required this.text,
    required this.lang,
    this.provisional = false,
  });

  final String? audioUrl;
  final String? audioKind;
  final String text;
  final String lang;
  final bool provisional;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (audioUrl == null) {
      return ListenButton(
        text: withProvisionalNote(text, provisional: provisional),
        mode: ListenMode.content,
        contentLang: spokenLang(lang, provisional: provisional),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: () async {
            try {
              await ref.read(audioPlaybackServiceProvider).playUrl(ApiClient.mediaUrl(audioUrl!));
            } catch (_) {
              if (context.mounted) showSnack(context, S.listenUnavailable);
            }
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 28),
          label: const Text(S.play),
        ),
        IconButton(
          tooltip: S.stop,
          icon: const Icon(Icons.stop_rounded),
          onPressed: () => ref.read(audioPlaybackServiceProvider).stop(),
        ),
        Chip(
          avatar: Icon(audioKind == 'synthetic' ? Icons.smart_toy_rounded : Icons.person_rounded, size: 18),
          label: Text(audioKind == 'synthetic' ? S.synthVoice : S.humanVoice),
          backgroundColor: audioKind == 'synthetic' ? theme.colorScheme.tertiaryContainer : null,
        ),
        if (provisional)
          const ListenButton(text: S.provisionalNote, compact: true, mode: ListenMode.content, contentLang: 'fr'),
      ],
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({required this.state, required this.lang});

  final AssistantState state;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBanner(text: S.offlineAnswerNote, icon: Icons.wifi_off_rounded),
        const SizedBox(height: AppSpacing.md),
        if (state.offlineDanger.isNotEmpty) ...[
          DangerBanner(signs: state.offlineDanger.map((s) => s.toHit()).toList(), contentLang: lang),
          const SizedBox(height: AppSpacing.md),
        ],
        if (state.offlineFaq.isNotEmpty) ...[
          const SectionTitle(S.closeQuestions),
          for (final entry in state.offlineFaq) FaqTile(entry: entry, lang: lang),
        ] else
          const InfoBanner(text: S.noFaqOffline),
      ],
    );
  }
}

class FaqTile extends StatelessWidget {
  const FaqTile({super.key, required this.entry, required this.lang});

  final FaqEntry entry;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        leading: Icon(
          entry.isDangerTopic ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
          color: entry.isDangerTopic ? AppTheme.danger : theme.colorScheme.primary,
        ),
        title: Text(entry.question, style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(entry.answer, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: AppSpacing.sm),
          if (entry.provisional) ...[ProvisionalNote(source: entry.source), const SizedBox(height: AppSpacing.sm)],
          AudioAnswerRow(
            audioUrl: entry.audioUrl,
            audioKind: entry.audioKind,
            text: entry.answer,
            lang: lang,
            provisional: entry.provisional,
          ),
        ],
      ),
    );
  }
}
