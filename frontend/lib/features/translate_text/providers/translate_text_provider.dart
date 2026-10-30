import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

import '../../../core/providers.dart';
import '../../../core/translation_engine.dart';

class TranslateTextState {
  const TranslateTextState({
    this.sourceLang = 'fr',
    this.targetLang = 'mos',
    this.translation,
    this.isTranslating = false,
    this.error,
    this.translationEngine = TranslationEngine.verified,
  });

  final String sourceLang;
  final String targetLang;
  final String? translation;
  final bool isTranslating;
  final String? error;

  /// Quel moteur a produit la traduction actuellement affichée. Le lecteur
  /// doit pouvoir le savoir : les deux moteurs ne rendent pas les mêmes
  /// phrases, et un seul a été relu par un locuteur natif. Le moteur CHOISI
  /// pour la prochaine traduction, lui, vit dans `translationEngineProvider`,
  /// partagé par tous les écrans.
  final TranslationEngine translationEngine;

  TranslateTextState copyWith({
    String? sourceLang,
    String? targetLang,
    String? translation,
    bool? isTranslating,
    String? error,
    TranslationEngine? translationEngine,
    bool clearTranslation = false,
    bool clearError = false,
  }) => TranslateTextState(
    sourceLang: sourceLang ?? this.sourceLang,
    targetLang: targetLang ?? this.targetLang,
    translation: clearTranslation ? null : (translation ?? this.translation),
    isTranslating: isTranslating ?? this.isTranslating,
    error: clearError ? null : (error ?? this.error),
    translationEngine: translationEngine ?? this.translationEngine,
  );
}

class TranslateTextController extends AutoDisposeNotifier<TranslateTextState> {
  CancelToken? _cancelToken;

  @override
  TranslateTextState build() {
    ref.onDispose(() => _cancelToken?.cancel());
    // Changement de moteur : la traduction affichée est effacée. Elle vient
    // de l'autre moteur, la laisser sous un choix qui a changé induirait en
    // erreur sur son origine.
    ref.listen(translationEngineProvider, (previous, next) {
      if (previous != next) state = state.copyWith(clearTranslation: true);
    });
    // Agent (français) vers la langue de la femme, par défaut le mooré.
    return const TranslateTextState(sourceLang: 'fr', targetLang: 'mos');
  }

  void setSourceLang(String lang) => state = state.copyWith(sourceLang: lang, clearTranslation: true);

  void setTargetLang(String lang) => state = state.copyWith(targetLang: lang, clearTranslation: true);

  Future<void> translate(String text) async {
    if (text.trim().isEmpty) return;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final engine = effectiveEngine(ref);
    state = state.copyWith(isTranslating: true, clearError: true, clearTranslation: true);
    try {
      final result = await ref
          .read(translationApiProvider)
          .translateText(
            text: text,
            sourceLang: state.sourceLang,
            targetLang: state.targetLang,
            engine: engine,
            cancelToken: cancelToken,
          );
      state = state.copyWith(translation: result, isTranslating: false, translationEngine: engine);
    } on RequestCancelledException {
      // Annulation volontaire : retour a l'etat initial, sans bandeau rouge.
      state = state.copyWith(isTranslating: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isTranslating: false);
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() => _cancelToken?.cancel();
}

// `autoDispose` : l'etat repart de zero a chaque ouverture de l'ecran.
// Sans ca, la traduction precedente etait deja affichee a la reouverture,
// sous un champ de saisie vide — on ne savait plus si c'etait un resultat
// frais ou un vieux reste, et les langues preferees n'etaient jamais relues.
final translateTextControllerProvider = AutoDisposeNotifierProvider<TranslateTextController, TranslateTextState>(
  TranslateTextController.new,
);
