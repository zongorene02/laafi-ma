{{flutter_js}}
{{flutter_build_config}}

// Moteur de rendu forcé sur CanvasKit.
//
// Flutter 3.47 embarque plusieurs moteurs de rendu web (canvaskit, skwasm,
// skwasm_heavy, wimp) et en choisit un automatiquement selon le navigateur.
// Sur cette machine (Chrome 150, Edge 152), le choix automatique aboutit à une
// PAGE BLANCHE : le moteur démarre, les polices et CanvasKit se chargent, le
// `flt-glass-pane` est créé — mais aucune image n'est jamais peinte, sans la
// moindre erreur en console.
//
// Diagnostic fait le 2026-09-08, et reproduit avec une application Flutter
// neuve (`flutter create`) ne contenant aucune ligne de ce projet : ce n'est
// donc pas un bug applicatif. Forcer explicitement CanvasKit rétablit
// l'affichage immédiatement.
//
// À réévaluer après une montée de version de Flutter : si le choix automatique
// redevient fiable, ce fichier peut simplement être supprimé (Flutter
// régénérera son bootstrap par défaut).
//
// `canvasKitBaseUrl` : le moteur vient de notre site et non du CDN de Google. Si
// ce CDN est injoignable (DNS, pare-feu, réseau lent), la page resterait vide.
Promise.resolve(
  _flutter.loader.load({
    config: {
      renderer: "canvaskit",
      canvasKitBaseUrl: "canvaskit/",
    },
  }),
).catch(function (error) {
  console.error(error);
  window.laafiBootFailed && window.laafiBootFailed();
});
