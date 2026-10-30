import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/data/audio_playback_service.dart';
import '../providers.dart';
import '../storage/json_store.dart';
import '../storage/vault.dart';

enum ProfileKind { real, decoy }

/// État de la session : verrouillée, ou ouverte sur le profil réel ou leurre.
class SessionState {
  const SessionState({this.profile, this.store, this.helpUnlocked = false, this.profileIndex = 1});

  const SessionState.locked() : profile = null, store = null, helpUnlocked = false, profileIndex = 1;

  final ProfileKind? profile;

  /// Numéro du profil réel ouvert (1 à 3, téléphone partagé). Vaut 1 pour le
  /// leurre.
  final int profileIndex;

  /// Coffre chiffré du profil ouvert.
  final JsonStore? store;

  /// La page Aide a déjà été ouverte avec son code depuis le déverrouillage.
  final bool helpUnlocked;

  bool get unlocked => profile != null;
  bool get isDecoy => profile == ProfileKind.decoy;
}

class SessionController extends Notifier<SessionState> {
  int _autoLockSuspended = 0;

  @override
  SessionState build() => const SessionState.locked();

  Future<void> unlock(ProfileKind kind, {int profile = 1}) async {
    final index = kind == ProfileKind.real ? profile : 1;
    final name = kind == ProfileKind.real ? VaultName.profile(index) : VaultName.decoy;
    final store = await ref.read(vaultProvider).open(name);
    state = SessionState(profile: kind, store: store, profileIndex: index);
  }

  /// Verrouillage immédiat (sortie rapide, mise en arrière-plan). L'audio en
  /// cours est coupé : une réponse de santé qui continue de parler après la
  /// sortie rapide trahirait l'application.
  void lock() {
    try {
      ref.read(audioPlaybackServiceProvider).stop();
    } catch (_) {
      // Pas de lecteur audio (tests) : rien à couper.
    }
    state = const SessionState.locked();
  }

  void unlockHelp() => state = SessionState(
    profile: state.profile,
    store: state.store,
    helpUnlocked: true,
    profileIndex: state.profileIndex,
  );

  /// Appelé quand l'application passe en arrière-plan.
  void onBackground() {
    if (_autoLockSuspended == 0 && state.unlocked) lock();
  }

  /// Le sélecteur de photos, l'appareil photo ou le sélecteur de fichiers font
  /// passer l'application en arrière-plan : sans cette suspension, elle se
  /// verrouillerait au milieu du choix et la photo serait perdue.
  Future<T> withoutAutoLock<T>(Future<T> Function() action) async {
    _autoLockSuspended++;
    try {
      return await action();
    } finally {
      // Laisse le temps à l'événement « retour au premier plan » d'arriver
      // avant de réarmer le verrouillage automatique.
      Future<void>.delayed(const Duration(seconds: 1), () => _autoLockSuspended--);
    }
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Coffre du profil ouvert. Verrouillé : un coffre vide en mémoire, pour que
/// les écrans encore en cours de démontage ne plantent pas.
final profileStoreProvider = Provider<JsonStore>((ref) => ref.watch(sessionProvider).store ?? MemoryJsonStore());
