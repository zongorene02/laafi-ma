import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/security/session.dart';
import '../../core/theme/app_theme.dart';
import 'listen_button.dart';

/// Verrouille tout de suite et affiche l'écran neutre (calculatrice ou code).
void quickExit(BuildContext context, WidgetRef ref) {
  ref.read(sessionProvider.notifier).lock();
  GoRouter.of(context).go('/lock');
}

/// Action « Sortie rapide » de la barre du haut, présente sur tous les écrans.
class QuickExitAction extends ConsumerWidget {
  const QuickExitAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: S.quickExit,
      iconSize: 28,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(Icons.visibility_off_rounded),
      onPressed: () => quickExit(context, ref),
    );
  }
}

/// Grand bouton rouge « Sortie rapide », toujours visible en bas des écrans de
/// la page Aide (module 3).
class QuickExitBar extends ConsumerWidget {
  const QuickExitBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: () => quickExit(context, ref),
          icon: const Icon(Icons.visibility_off_rounded, size: 28),
          label: const Text(S.quickExit),
        ),
      ),
    );
  }
}

/// Coquille commune : titre, bouton « Écouter » (texte de l'écran), sortie
/// rapide, contenu limité en largeur pour rester lisible sur grand écran.
class LaafiScaffold extends StatelessWidget {
  const LaafiScaffold({
    super.key,
    required this.title,
    required this.body,
    this.listenText,
    this.actions,
    this.floatingActionButton,
    this.protectedArea = false,
    this.showBack = true,
    this.backTo = '/home',
    this.scrollable = true,
  });

  final String title;
  final Widget body;
  final String? listenText;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// Écrans de la page Aide : grand bouton « Sortie rapide » en bas.
  final bool protectedArea;
  final bool showBack;

  /// Destination du bouton retour quand rien n'est en dessous dans la pile.
  final String backTo;

  /// `false` quand le contenu gère son propre défilement (listes).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.formMaxWidth),
        child: scrollable
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                child: body,
              )
            : body,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                tooltip: S.back,
                iconSize: 28,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.canPop() ? context.pop() : context.go(backTo),
              )
            : null,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          if (listenText != null) ListenButton(text: listenText!, compact: true),
          ...?actions,
          const QuickExitAction(),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: protectedArea ? const QuickExitBar() : null,
      body: SafeArea(top: false, child: content),
    );
  }
}

/// Grande tuile pictogramme (accueil, sommaire du carnet…), avec son propre
/// bouton « Écouter ».
class PictoTile extends StatelessWidget {
  const PictoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.listenText,
    this.big = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String? listenText;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = big ? 56.0 : 40.0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: iconSize * 1.7,
                    height: iconSize * 1.7,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(icon, size: iconSize, color: color),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (big ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (listenText != null) Positioned(top: 4, right: 4, child: ListenButton(text: listenText!, compact: true)),
          ],
        ),
      ),
    );
  }
}

/// Grille de tuiles qui s'adapte à la largeur (2 colonnes sur téléphone).
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 160, this.aspectRatio = 0.95});

  final List<Widget> children;
  final double minTileWidth;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(2, 4);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}

/// Bandeau d'information (gris), d'avertissement (orange) ou de danger (rouge).
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.icon = Icons.info_outline_rounded, this.color, this.child});

  final String text;
  final IconData icon;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tint),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            ],
          ),
          if (child != null) ...[const SizedBox(height: AppSpacing.sm), child!],
        ],
      ),
    );
  }
}

/// Titre de section avec son bouton « Écouter ».
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.listen = true});

  final String text;
  final bool listen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
          if (listen) ListenButton(text: text, compact: true),
        ],
      ),
    );
  }
}

/// Valeur mise en avant (estimation de date, semaine de grossesse…).
class BigValueCard extends StatelessWidget {
  const BigValueCard({super.key, required this.label, required this.value, this.note, this.color});

  final String label;
  final String value;
  final String? note;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    final spoken = '$label : $value. ${note ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(color: tint, fontWeight: FontWeight.w900),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(note!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
            ListenButton(text: spoken, compact: true),
          ],
        ),
      ),
    );
  }
}

/// Affichage commun des erreurs de chargement, avec bouton « Réessayer ».
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return InfoBanner(
      text: message,
      icon: Icons.wifi_off_rounded,
      color: Theme.of(context).colorScheme.error,
      child: onRetry == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(S.retry),
              ),
            ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String message, {String confirmLabel = S.delete}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message, style: Theme.of(context).textTheme.titleMedium),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(S.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
