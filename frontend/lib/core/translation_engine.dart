import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

/// Les deux moteurs de traduction proposés par le serveur.
///
/// Ils ne rendent pas exactement les mêmes phrases : le moteur VÉRIFIÉ est
/// celui dont les traductions en Mooré ont été relues par un locuteur natif,
/// le moteur RAPIDE (quantifié, 7 à 20 fois plus rapide) ne l'a pas encore été.
/// L'utilisateur choisit en connaissance de cause, sur chaque écran de
/// traduction — jamais l'application à sa place.
enum TranslationEngine {
  verified('verified', 'Vérifiée'),
  fast('fast', 'Rapide');

  const TranslationEngine(this.apiValue, this.label);

  /// Valeur attendue par le paramètre `mode` des endpoints de traduction.
  final String apiValue;
  final String label;

  static TranslationEngine fromApi(String? value) => value == fast.apiValue ? fast : verified;
}

/// Moteur choisi par l'utilisateur, CONSERVÉ d'un lancement à l'autre et
/// partagé par tous les écrans : quelqu'un qui préfère la réponse rapide la
/// veut aussi bien pour un texte que pour un message vocal, sans refaire le
/// choix à chaque écran. Il reste modifiable sur chacun d'eux.
///
/// Stocké sur l'appareil, comme le thème (voir `ThemeModeController`).
class TranslationEngineController extends Notifier<TranslationEngine> {
  static const _storageKey = 'translation_engine';

  @override
  TranslationEngine build() {
    _restore();
    return TranslationEngine.verified;
  }

  Future<void> _restore() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getString(_storageKey);
      if (stored != null) state = TranslationEngine.fromApi(stored);
    } catch (_) {
      // Stockage indisponible : le moteur vérifié reste le repli, c'est
      // justement le comportement par défaut voulu.
    }
  }

  Future<void> select(TranslationEngine engine) async {
    state = engine;
    try {
      await (await SharedPreferences.getInstance()).setString(_storageKey, engine.apiValue);
    } catch (_) {
      // Le choix s'applique de toute façon pour cette session.
    }
  }
}

final translationEngineProvider = NotifierProvider<TranslationEngineController, TranslationEngine>(
  TranslationEngineController.new,
);

/// Le serveur a-t-il les modèles du moteur rapide (1,2 Go, pas installés
/// partout) ? Demandé une seule fois par session via `/health`, accessible
/// sans compte : le choix s'affiche aussi pour un visiteur non connecté.
///
/// Les deux options restent TOUJOURS visibles ; seule l'option rapide se grise
/// (avec l'explication) quand le serveur ne la propose pas — mieux vaut un
/// choix expliqué qu'une option qui apparaît et disparaît d'un serveur à
/// l'autre sans qu'on sache pourquoi.
final fastEngineAvailableProvider = FutureProvider<bool>((ref) {
  return ref.read(translationApiProvider).fastModeAvailable();
});

/// Moteur RÉELLEMENT utilisé pour la prochaine requête : le choix de
/// l'utilisateur, sauf si le serveur ne propose pas le moteur rapide — on
/// envoie alors "verified" plutôt qu'une requête vouée à l'erreur 503.
/// Tant que la réponse de `/health` n'est pas arrivée, on respecte le choix.
TranslationEngine effectiveEngine(Ref ref) {
  final chosen = ref.read(translationEngineProvider);
  final fastAvailable = ref.read(fastEngineAvailableProvider).valueOrNull ?? true;
  return chosen == TranslationEngine.fast && !fastAvailable ? TranslationEngine.verified : chosen;
}
