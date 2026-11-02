import 'package:flutter/material.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';

/// Mention montrée avec tout contenu `provisional` : tiré d'une source
/// publique, relu par aucune sage-femme (docs/API.md). Ce contenu n'existe
/// qu'en français.
class ProvisionalNote extends StatelessWidget {
  const ProvisionalNote({super.key, this.source});

  /// Référence complète, affichée en petit quand il y a la place.
  final String? source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.provisionalNote, style: style?.copyWith(fontWeight: FontWeight.w700)),
              if (source != null) Text(source!, style: style),
            ],
          ),
        ),
      ],
    );
  }
}

/// Texte lu par « Écouter » : la mention est dite aussi, pour celles qui ne
/// lisent pas.
String withProvisionalNote(String text, {required bool provisional}) =>
    provisional ? '$text ${S.provisionalNote}' : text;

/// Langue de lecture : le contenu `provisional` est toujours en français,
/// même quand la femme a choisi le mooré ou le dioula.
String spokenLang(String lang, {required bool provisional}) => provisional ? 'fr' : lang;
