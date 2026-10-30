import 'package:flutter/material.dart';

import '../../core/constants/languages.dart';
import '../../core/theme/app_theme.dart';

/// Codes des langues nationales, mises en valeur dans les listes : c'est la
/// raison d'être du projet.
const _nationalLanguageCodes = {'mos', 'dyu', 'bam'};

/// Sélecteur de langue réutilisé partout (traduction texte, voix, documents,
/// vidéo, réglages) — un seul widget à faire évoluer si la liste de langues
/// change.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.languages,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Petit libellé au-dessus du nom de la langue (« De », « Vers »).
  final String? label;

  /// Sous-ensemble optionnel (ex: langues du clonage vocal uniquement).
  final List<AppLanguage>? languages;

  /// `false` pendant un enregistrement ou une conversation en cours : changer
  /// de langue en plein milieu n'aurait aucun effet (la langue est fixée à
  /// l'ouverture du canal côté serveur). Le sélecteur se GRISE alors, au lieu
  /// de rester d'apparence normale tout en ignorant les clics — un contrôle
  /// qui a l'air actif mais ne répond pas donne l'impression que l'app est
  /// cassée.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = languages ?? kSupportedLanguages;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Text(
                label!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: options.any((lang) => lang.code == value) ? value : null,
                isExpanded: true,
                isDense: true,
                borderRadius: BorderRadius.circular(AppRadius.md),
                icon: const Icon(Icons.expand_more_rounded),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                items: [
                  for (final lang in options)
                    DropdownMenuItem(
                      value: lang.code,
                      child: Row(
                        children: [
                          Flexible(child: Text(lang.name, overflow: TextOverflow.ellipsis)),
                          if (_nationalLanguageCodes.contains(lang.code)) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: theme.colorScheme.tertiary, shape: BoxShape.circle),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
                // Un `onChanged: null` suffit à Material pour appliquer le
                // style désactivé standard, y compris pour les lecteurs d'écran.
                onChanged: enabled
                    ? (code) {
                        if (code != null) onChanged(code);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne « langue source -> langue cible » avec un bouton pour inverser les
/// deux — motif répété sur presque tous les écrans de traduction.
class LanguagePairSelector extends StatefulWidget {
  const LanguagePairSelector({
    super.key,
    required this.sourceLang,
    required this.targetLang,
    required this.onSourceChanged,
    required this.onTargetChanged,
    this.languages,
    this.enabled = true,
  });

  final String sourceLang;
  final String targetLang;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onTargetChanged;
  final List<AppLanguage>? languages;
  final bool enabled;

  @override
  State<LanguagePairSelector> createState() => _LanguagePairSelectorState();
}

class _LanguagePairSelectorState extends State<LanguagePairSelector> {
  /// Demi-tours accumulés par le bouton d'inversion : l'icône pivote à chaque
  /// appui, ce qui confirme visuellement que les langues ont bien été
  /// échangées (le changement de texte seul passe facilement inaperçu).
  double _turns = 0;

  void _swap() {
    setState(() => _turns += 0.5);
    final source = widget.sourceLang;
    widget.onSourceChanged(widget.targetLang);
    widget.onTargetChanged(source);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: LanguagePicker(
                label: 'De',
                value: widget.sourceLang,
                onChanged: widget.onSourceChanged,
                languages: widget.languages,
                enabled: widget.enabled,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: LanguagePicker(
                label: 'Vers',
                value: widget.targetLang,
                onChanged: widget.onTargetChanged,
                languages: widget.languages,
                enabled: widget.enabled,
              ),
            ),
          ],
        ),
        // Bouton posé À CHEVAL sur les deux sélecteurs : il se lit tout de
        // suite comme « échanger ces deux-là », sans libellé.
        Material(
          color: theme.colorScheme.surface,
          shape: CircleBorder(side: BorderSide(color: theme.colorScheme.outlineVariant)),
          child: IconButton(
            tooltip: 'Inverser les langues',
            onPressed: widget.enabled ? _swap : null,
            icon: AnimatedRotation(
              turns: _turns,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: const Icon(Icons.swap_horiz_rounded),
            ),
            color: theme.colorScheme.primary,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
