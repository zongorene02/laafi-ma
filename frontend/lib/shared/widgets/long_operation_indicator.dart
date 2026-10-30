import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Attente longue, rendue supportable.
///
/// Les traductions média sont lentes par nature sur un serveur sans carte
/// graphique : une vidéo courte demande déjà plus d'une minute, un document
/// plusieurs dizaines de secondes. Un simple `CircularProgressIndicator`
/// pendant tout ce temps est indiscernable d'une application figée — au bout
/// de trente secondes, l'utilisateur ferme l'écran (ou l'app) en pensant que
/// c'est planté, et le travail déjà fait est perdu.
///
/// Ce widget affiche donc trois choses que le spinner seul ne donnait pas :
/// 1. l'ENVOI du fichier avec un vrai pourcentage (la seule phase réellement
///    mesurable) ;
/// 2. le TEMPS ÉCOULÉ pendant le travail du serveur, pour montrer que ça
///    avance, avec la durée typique en repère ;
/// 3. un bouton ANNULER, parce qu'une attente qu'on ne peut pas interrompre
///    est une attente subie.
class LongOperationIndicator extends StatefulWidget {
  const LongOperationIndicator({
    super.key,
    required this.uploadProgress,
    required this.onCancel,
    required this.serverWorkLabel,
    this.typicalDuration,
  });

  /// Fraction envoyée (0 à 1) pendant le téléversement, `null` quand le
  /// serveur travaille (avancement non mesurable).
  final double? uploadProgress;
  final VoidCallback onCancel;

  /// Ce que fait le serveur, en clair : « Transcription, traduction et
  /// synthèse vocale… ». Nommer l'étape en cours vaut mieux qu'un
  /// « Chargement… » qui n'apprend rien.
  final String serverWorkLabel;

  /// Durée habituelle observée, affichée comme repère ("≈ 2 min"). Une
  /// estimation honnête vaut mieux qu'un faux compte à rebours précis.
  final Duration? typicalDuration;

  @override
  State<LongOperationIndicator> createState() => _LongOperationIndicatorState();
}

class _LongOperationIndicatorState extends State<LongOperationIndicator> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return minutes > 0 ? '$minutes min ${seconds.toString().padLeft(2, '0')} s' : '$seconds s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = widget.uploadProgress;
    final isUploading = progress != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            // Barre déterminée pendant l'envoi, indéterminée ensuite : la
            // forme même de l'indicateur dit honnêtement si l'app connaît ou
            // non l'avancement, au lieu d'inventer un pourcentage.
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          isUploading ? 'Envoi du fichier… ${(progress * 100).round()} %' : widget.serverWorkLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (!isUploading) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.typicalDuration == null
                ? _formatDuration(_stopwatch.elapsed)
                : '${_formatDuration(_stopwatch.elapsed)} · habituellement ≈ ${_formatDuration(widget.typicalDuration!)}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TextButton.icon(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Annuler'),
        ),
      ],
    );
  }
}
