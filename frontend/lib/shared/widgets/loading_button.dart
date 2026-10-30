import 'package:flutter/material.dart';

/// Bouton qui affiche un indicateur de progression à la place de son texte
/// pendant une action asynchrone, et se désactive pour empêcher un double
/// appui (ex: double inscription) — comportement qu'on aurait sinon dû
/// répéter à la main sur chaque écran avec un appel réseau.
class LoadingButton extends StatelessWidget {
  const LoadingButton({super.key, required this.label, required this.onPressed, this.isLoading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        // `onPrimary` du thème plutôt qu'un blanc en dur : en thème sombre, le
        // bouton devient clair et un indicateur blanc y était quasi invisible
        // — l'utilisateur ne voyait plus que le bouton avait réagi.
        child: isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Theme.of(context).colorScheme.onPrimary),
              )
            : Text(label),
      ),
    );
  }
}
