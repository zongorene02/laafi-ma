import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/translation_engine.dart';

/// Choix du moteur de traduction, présent sur TOUS les écrans de traduction.
///
/// Deux cartes côte à côte plutôt qu'un simple interrupteur : chacune dit ce
/// qu'on gagne et ce qu'on cède (qualité relue contre réponse immédiate). Un
/// réglage nommé « rapide » sans contrepartie laisserait croire qu'il n'y a
/// aucune raison de ne pas l'activer — or ses traductions n'ont pas encore été
/// relues par un locuteur natif.
class EngineSelector extends ConsumerWidget {
  const EngineSelector({super.key, this.enabled = true});

  /// `false` pendant une traduction : changer de moteur en cours de route
  /// n'aurait aucun effet sur la requête déjà partie.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(translationEngineProvider);
    final fastAvailable = ref.watch(fastEngineAvailableProvider).valueOrNull ?? true;
    final effective = selected == TranslationEngine.fast && !fastAvailable ? TranslationEngine.verified : selected;

    void select(TranslationEngine engine) => ref.read(translationEngineProvider.notifier).select(engine);

    return Semantics(
      label: 'Moteur de traduction',
      child: Row(
        children: [
          Expanded(
            child: _EngineOption(
              icon: Icons.verified_rounded,
              title: 'Vérifiée',
              subtitle: 'Relue par un locuteur natif · plus lente',
              accent: Theme.of(context).colorScheme.primary,
              selected: effective == TranslationEngine.verified,
              onTap: enabled ? () => select(TranslationEngine.verified) : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _EngineOption(
              icon: Icons.bolt_rounded,
              title: 'Rapide',
              subtitle: fastAvailable ? 'Quelques secondes · pas encore relue' : 'Indisponible sur ce serveur',
              accent: Theme.of(context).colorScheme.tertiary,
              selected: effective == TranslationEngine.fast,
              onTap: enabled && fastAvailable ? () => select(TranslationEngine.fast) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineOption extends StatelessWidget {
  const _EngineOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disabled = onTap == null && !selected;

    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? accent : colorScheme.outlineVariant, width: selected ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Opacity(
              opacity: disabled ? 0.5 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: selected ? accent : colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: selected ? accent : colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (selected) Icon(Icons.check_circle_rounded, size: 18, color: accent),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Étiquette posée sur un résultat : le lecteur doit savoir quel moteur a
/// produit ce texte — les deux ne rendent pas les mêmes phrases, et un seul a
/// été relu par un locuteur natif.
class EngineBadge extends StatelessWidget {
  const EngineBadge({super.key, required this.engine});

  final TranslationEngine engine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFast = engine == TranslationEngine.fast;
    final color = isFast ? theme.colorScheme.tertiary : theme.colorScheme.primary;
    return Tooltip(
      message: isFast
          ? 'Produite par le moteur rapide, pas encore relue par un locuteur natif'
          : 'Produite par le moteur vérifié, relu par un locuteur natif',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isFast ? Icons.bolt_rounded : Icons.verified_rounded, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              isFast ? 'Rapide' : 'Vérifiée',
              style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
