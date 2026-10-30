import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/engine_selector.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/language_picker.dart';
import '../../../shared/widgets/long_operation_indicator.dart';
import '../../../shared/widgets/page_layout.dart';
import '../../translate_voice/presentation/widgets/pulsing_mic_button.dart';
import '../providers/voice_message_provider.dart';

class TranslateVoiceMessageScreen extends ConsumerWidget {
  const TranslateVoiceMessageScreen({super.key});

  Future<void> _pickAndTranslateFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final file = result?.files.single;
    if (file?.bytes == null) return;

    await ref
        .read(voiceMessageControllerProvider.notifier)
        .translateAudioFile(fileBytes: file!.bytes!, filename: file.name);
  }

  Future<void> _startRecording(BuildContext context, WidgetRef ref) async {
    await ref.read(voiceMessageControllerProvider.notifier).startRecording();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceMessageControllerProvider);
    final controller = ref.read(voiceMessageControllerProvider.notifier);
    final theme = Theme.of(context);

    final isRecording = state.status == VoiceMessageStatus.recording;
    final isTranslating = state.status == VoiceMessageStatus.translating;
    final isBusy = isRecording || isTranslating;

    return TranslationPage(
      title: 'Message vocal',
      subtitle: 'Enregistrez un message ou importez un fichier audio.',
      icon: Icons.mic_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormSection(
            label: 'Langues',
            child: LanguagePairSelector(
              sourceLang: state.sourceLang,
              targetLang: state.targetLang,
              onSourceChanged: controller.setSourceLang,
              onTargetChanged: controller.setTargetLang,
              enabled: !isBusy,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FormSection(
            label: 'Moteur',
            child: EngineSelector(enabled: !isBusy),
          ),
          if (state.canPreserveVoice) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: SwitchListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                secondary: Icon(Icons.record_voice_over_rounded, color: theme.colorScheme.primary),
                title: const Text('Garder ma voix'),
                subtitle: const Text('Clonage vocal — la traduction est dite avec votre timbre'),
                value: state.preserveVoice,
                onChanged: isBusy ? null : controller.setPreserveVoice,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (state.errorMessage != null) ...[
            ErrorBanner(message: state.errorMessage!),
            const SizedBox(height: AppSpacing.lg),
          ],
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Center(
              child: isTranslating
                  // Pendant la traduction (jusqu'à ~70 s sur un serveur sans
                  // carte graphique avec le moteur vérifié), on remplace le
                  // micro par une vraie attente : progression de l'envoi,
                  // temps écoulé, et surtout un bouton pour annuler.
                  ? LongOperationIndicator(
                      uploadProgress: state.uploadProgress,
                      onCancel: controller.cancel,
                      serverWorkLabel: 'Transcription, traduction et synthèse vocale…',
                      typicalDuration: const Duration(seconds: 70),
                    )
                  : Column(
                      children: [
                        PulsingMicButton(
                          isActive: isRecording,
                          isConnecting: false,
                          onTap: isRecording ? controller.stopAndTranslate : () => _startRecording(context, ref),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(switch (state.status) {
                          VoiceMessageStatus.idle => 'Appuyez pour enregistrer',
                          VoiceMessageStatus.recording => 'Enregistrement… appuyez pour traduire',
                          VoiceMessageStatus.translating => 'Traduction en cours…',
                          VoiceMessageStatus.done => 'Terminé — appuyez pour recommencer',
                          VoiceMessageStatus.error => 'Réessayez',
                        }, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        if (!isRecording) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                child: Text(
                                  'ou',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          OutlinedButton.icon(
                            onPressed: () => _pickAndTranslateFile(context, ref),
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Importer un fichier audio'),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          if (state.status == VoiceMessageStatus.done) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      EngineBadge(engine: state.resultEngine),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Réécouter',
                        icon: const Icon(Icons.volume_up_rounded),
                        onPressed: controller.replay,
                      ),
                    ],
                  ),
                  Text(
                    state.sourceText ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(state.translatedText ?? '', style: theme.textTheme.titleMedium?.copyWith(height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: controller.reset, child: const Text('Nouveau message')),
          ],
        ],
      ),
    );
  }
}
