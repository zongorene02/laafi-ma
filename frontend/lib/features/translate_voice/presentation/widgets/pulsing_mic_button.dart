import 'package:flutter/material.dart';

/// Gros bouton micro, avec un halo qui pulse doucement pendant l'écoute —
/// signal visuel clair que l'app enregistre vraiment, sans avoir besoin
/// d'une vraie visualisation de forme d'onde (plus complexe, pas
/// indispensable pour comprendre l'état du système).
class PulsingMicButton extends StatefulWidget {
  const PulsingMicButton({super.key, required this.isActive, required this.isConnecting, required this.onTap});

  final bool isActive;
  final bool isConnecting;
  final VoidCallback onTap;

  @override
  State<PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<PulsingMicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(PulsingMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  /// L'animation ne tourne QUE pendant l'écoute. Auparavant elle tournait en
  /// boucle dès la construction du widget : une image redessinée toutes les
  /// 16 ms en permanence, y compris quand le bouton est au repos — de la
  /// batterie consommée pour une pulsation invisible (le halo n'est dessiné
  /// que si `isActive`).
  void _syncAnimation() {
    if (widget.isActive) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _semanticLabel {
    if (widget.isConnecting) return 'Connexion en cours';
    return widget.isActive ? 'Arrêter la conversation' : 'Démarrer la conversation';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isActive ? theme.colorScheme.error : theme.colorScheme.primary;
    // Couleur du contenu POSÉ sur le cercle coloré : `onError`/`onPrimary`
    // suivent le thème (clair comme sombre), contrairement au blanc en dur
    // utilisé ici auparavant.
    final onColor = widget.isActive ? theme.colorScheme.onError : theme.colorScheme.onPrimary;

    // Le bouton principal de tout l'écran ne peut pas être un simple
    // `GestureDetector` : pour un lecteur d'écran, c'était un dessin muet,
    // sans nom, sans indication qu'on peut appuyer dessus, et sans dire s'il
    // écoute déjà. `Semantics` lui donne un nom qui change avec l'état, et
    // `button: true` le rend annonçable et activable comme un vrai bouton.
    return Semantics(
      button: true,
      enabled: !widget.isConnecting,
      toggled: widget.isActive,
      label: _semanticLabel,
      child: GestureDetector(
        onTap: widget.isConnecting ? null : widget.onTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = widget.isActive ? 1.0 + (_controller.value * 0.15) : 1.0;
            return Stack(
              alignment: Alignment.center,
              children: [
                if (widget.isActive)
                  Transform.scale(
                    scale: scale + 0.3,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
                    ),
                  ),
                Transform.scale(scale: widget.isActive ? scale : 1.0, child: child),
              ],
            );
          },
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: widget.isConnecting
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: CircularProgressIndicator(color: onColor, strokeWidth: 3),
                  )
                : Icon(widget.isActive ? Icons.stop_rounded : Icons.mic_rounded, color: onColor, size: 36),
          ),
        ),
      ),
    );
  }
}
