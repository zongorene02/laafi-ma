import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/audio_playback_service.dart';
import '../../../shared/widgets/engine_selector.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/language_picker.dart';
import '../../../shared/widgets/long_operation_indicator.dart';
import '../../../shared/widgets/page_layout.dart';
import '../providers/translate_text_provider.dart';

class TranslateTextScreen extends ConsumerStatefulWidget {
  const TranslateTextScreen({super.key, this.initialText});

  /// Texte déjà saisi depuis le champ de l'accueil : il est repris ici et la
  /// traduction démarre aussitôt, sans faire retaper ni recliquer.
  final String? initialText;

  @override
  ConsumerState<TranslateTextScreen> createState() => _TranslateTextScreenState();
}

class _TranslateTextScreenState extends ConsumerState<TranslateTextScreen> {
  late final _textController = TextEditingController(text: widget.initialText);
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
    if (widget.initialText?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _translate());
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    if (_textController.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    await ref.read(translateTextControllerProvider.notifier).translate(_textController.text);
  }

  Future<void> _speakTranslation(String text, String language) async {
    setState(() => _isSpeaking = true);
    try {
      final audio = await ref.read(translationApiProvider).textToSpeech(text: text, language: language);
      await ref.read(audioPlaybackServiceProvider).play(audio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Traduction copiée')));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(translateTextControllerProvider);
    final controller = ref.read(translateTextControllerProvider.notifier);
    final isWide = MediaQuery.sizeOf(context).width >= AppBreakpoints.wide;

    final input = _InputPanel(controller: _textController, enabled: !state.isTranslating, onSubmit: _translate);

    // Même pour une traduction de TEXTE, l'attente mérite mieux qu'un bouton
    // grisé : une vingtaine de secondes sur un serveur sans carte graphique
    // avec le moteur vérifié, et bien davantage la première fois qu'on traduit
    // vers le Mooré (le modèle spécialisé se charge alors à la demande). Sans
    // temps écoulé ni bouton d'annulation, rien ne distingue cette attente
    // d'une application figée.
    final Widget output = state.isTranslating
        ? _Panel(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: LongOperationIndicator(
                  uploadProgress: null,
                  onCancel: controller.cancel,
                  serverWorkLabel: state.targetLang == 'mos' || state.sourceLang == 'mos'
                      ? 'Traduction avec le modèle Mooré…\n(le tout premier appel charge le modèle)'
                      : 'Traduction en cours…',
                ),
              ),
            ),
          )
        : _OutputPanel(state: state, isSpeaking: _isSpeaking, onCopy: _copy, onSpeak: _speakTranslation);

    return TranslationPage(
      title: 'Texte',
      subtitle: 'Saisissez ou collez un texte, choisissez le moteur, traduisez.',
      icon: Icons.notes_rounded,
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
              enabled: !state.isTranslating,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FormSection(
            label: 'Moteur',
            child: EngineSelector(enabled: !state.isTranslating),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Sur grand écran, source et traduction côte à côte (lecture en
          // parallèle, comme une page bilingue) ; sur téléphone, l'une sous
          // l'autre.
          if (isWide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: input),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: output),
                ],
              ),
            )
          else
            input,
          const SizedBox(height: AppSpacing.md),
          if (!state.isTranslating)
            FilledButton.icon(
              onPressed: _textController.text.trim().isEmpty ? null : _translate,
              icon: const Icon(Icons.translate_rounded),
              label: const Text('Traduire'),
            ),
          if (state.error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBanner(message: state.error!)],
          if (!isWide && (state.isTranslating || state.translation != null)) ...[
            const SizedBox(height: AppSpacing.md),
            output,
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.highlighted = false});

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: highlighted ? theme.colorScheme.primary.withValues(alpha: 0.05) : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: highlighted ? theme.colorScheme.primary.withValues(alpha: 0.3) : theme.colorScheme.outlineVariant,
        ),
      ),
      child: child,
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({required this.controller, required this.enabled, required this.onSubmit});

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ctrl+Entrée lance la traduction : réflexe courant au clavier, qui
          // évite d'aller chercher le bouton à la souris.
          CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): onSubmit},
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofocus: controller.text.isEmpty,
              minLines: 5,
              maxLines: 12,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.5),
              decoration: const InputDecoration(
                hintText: 'Entrez le texte à traduire…',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.xs, AppSpacing.xs),
            child: Row(
              children: [
                Text(
                  '${controller.text.characters.length} caractères',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const Spacer(),
                if (controller.text.isNotEmpty && enabled)
                  IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: controller.clear,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputPanel extends StatelessWidget {
  const _OutputPanel({required this.state, required this.isSpeaking, required this.onCopy, required this.onSpeak});

  final TranslateTextState state;
  final bool isSpeaking;
  final ValueChanged<String> onCopy;
  final void Function(String text, String language) onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final translation = state.translation;

    if (translation == null) {
      return _Panel(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'La traduction apparaîtra ici',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ),
      );
    }

    return _Panel(
      highlighted: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EngineBadge(engine: state.translationEngine),
                const Spacer(),
                IconButton(
                  tooltip: 'Copier',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () => onCopy(translation),
                ),
                IconButton(
                  tooltip: 'Écouter',
                  icon: isSpeaking
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.volume_up_rounded, size: 20),
                  onPressed: isSpeaking ? null : () => onSpeak(translation, state.targetLang),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: SelectableText(
                translation,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
