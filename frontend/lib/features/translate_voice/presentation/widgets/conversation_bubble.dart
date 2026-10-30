import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/engine_selector.dart';
import '../../providers/voice_translate_provider.dart';

/// Un tour de conversation : le texte source (ce qui a été dit) au-dessus,
/// la traduction en dessous mise en avant — c'est elle que l'interlocuteur
/// veut lire/entendre. Un bouton permet de réécouter l'audio traduit.
class ConversationBubble extends StatelessWidget {
  const ConversationBubble({super.key, required this.turn, required this.onReplay});

  final ConversationTurn turn;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
          bottomRight: Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(AppRadius.sm),
        ),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(turn.sourceText, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  turn.translatedText,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
                ),
              ),
              if (turn.audioBytes != null)
                IconButton(
                  tooltip: 'Réécouter',
                  icon: const Icon(Icons.volume_up_rounded),
                  onPressed: onReplay,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          EngineBadge(engine: turn.engine),
        ],
      ),
    );
  }
}
