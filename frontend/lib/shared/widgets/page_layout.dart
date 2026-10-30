import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'laafi_scaffold.dart';

/// Logo de l'application : un pictogramme sur le dégradé de marque, suivi du
/// nom. Un seul widget pour que l'identité reste la même partout (barre
/// latérale, connexion, écran de démarrage).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36, this.showName = true, this.nameColor});

  final double size;
  final bool showName;

  /// Couleur du nom, pour un logo posé sur le dégradé (blanc) plutôt que sur
  /// le fond de l'application.
  final Color? nameColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.terracotta.withValues(alpha: 0.35),
                blurRadius: size * 0.4,
                offset: Offset(0, size * 0.12),
              ),
            ],
          ),
          child: Icon(Icons.favorite_rounded, color: Colors.white, size: size * 0.55),
        ),
        if (showName) ...[
          SizedBox(width: size * 0.3),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Laafi '),
                TextSpan(
                  text: 'Ma',
                  style: TextStyle(color: nameColor == null ? theme.colorScheme.tertiary : AppTheme.amber),
                ),
              ],
            ),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: size * 0.55,
              color: nameColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Corps d'écran centré et limité en largeur.
///
/// Sur un téléphone la contrainte n'est jamais atteinte ; dans un navigateur,
/// elle évite qu'un champ de saisie s'étire sur 1900 px et qu'une ligne de
/// texte devienne illisible (l'œil perd sa ligne au retour à la ligne).
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.formMaxWidth,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Coquille commune aux cinq écrans de traduction : en-tête avec retour, titre
/// et sous-titre explicatif, contenu défilant et centré.
///
/// Le bouton retour ne dépend pas de la pile de navigation : un écran ouvert
/// directement par son adresse (favori, lien partagé) n'a rien sous lui, et
/// la flèche par défaut de Flutter disparaissait alors — laissant
/// l'utilisateur sans aucun moyen évident de rejoindre l'accueil.
class TranslationPage extends StatelessWidget {
  const TranslationPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.actions,
    this.scrollable = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final List<Widget>? actions;

  /// `false` quand l'écran gère lui-même son défilement (conversation).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/agent'),
        ),
        actions: [
          ...?actions,
          const QuickExitAction(),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: scrollable
            ? SingleChildScrollView(
                child: PageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: AppSpacing.lg),
                      child,
                    ],
                  ),
                ),
              )
            : PageBody(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(child: child),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Bloc titré d'un formulaire : petit libellé au-dessus d'un contenu
/// (« Langues », « Moteur »…). Donne un rythme de lecture régulier aux écrans.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}
