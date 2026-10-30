import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/engine_selector.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/language_picker.dart';
import '../../../shared/widgets/page_layout.dart';
import '../providers/voice_translate_provider.dart';
import 'widgets/conversation_bubble.dart';
import 'widgets/pulsing_mic_button.dart';

class TranslateVoiceScreen extends ConsumerWidget {
  const TranslateVoiceScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    await ref.read(voiceConversationControllerProvider.notifier).start();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceConversationControllerProvider);
    final controller = ref.read(voiceConversationControllerProvider.notifier);
    final theme = Theme.of(context);

    return TranslationPage(
      title: 'Conversation',
      subtitle: 'Parlez : chaque phrase est traduite et prononcée dès que vous marquez une pause.',
      icon: Icons.graphic_eq_rounded,
      scrollable: false,
      actions: [
        if (state.turns.isNotEmpty)
          IconButton(
            tooltip: 'Effacer la conversation',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: controller.clearConversation,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Langues et moteur grisés pendant la conversation : ils sont fixés
          // à l'ouverture du WebSocket côté serveur.
          LanguagePairSelector(
            sourceLang: state.sourceLang,
            targetLang: state.targetLang,
            onSourceChanged: controller.setSourceLang,
            onTargetChanged: controller.setTargetLang,
            enabled: !state.isActive,
          ),
          const SizedBox(height: AppSpacing.sm),
          EngineSelector(enabled: !state.isActive),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: state.errorMessage!),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: state.turns.isEmpty
                  ? _EmptyState(isActive: state.isActive)
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: state.turns.length,
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final turn = state.turns[index];
                        return ConversationBubble(turn: turn, onReplay: () => controller.replayTurn(turn));
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              children: [
                PulsingMicButton(
                  isActive: state.status == ConversationStatus.listening,
                  isConnecting: state.status == ConversationStatus.connecting,
                  onTap: state.isActive ? controller.stop : () => _start(context, ref),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(switch (state.status) {
                  ConversationStatus.idle => 'Appuyez pour parler',
                  ConversationStatus.connecting => 'Connexion…',
                  ConversationStatus.listening => 'En écoute — appuyez pour arrêter',
                  ConversationStatus.error => 'Réessayez',
                }, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            Text(
              isActive ? 'Parlez, la traduction apparaîtra ici' : 'Démarrez une conversation pour commencer',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
