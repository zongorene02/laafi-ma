import 'package:flutter/material.dart';

/// Affichage uniforme d'un message d'erreur (échec réseau, validation...) —
/// même style partout dans l'app plutôt qu'un SnackBar tantôt, un Text rouge
/// tantôt.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colorScheme.errorContainer, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: colorScheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
