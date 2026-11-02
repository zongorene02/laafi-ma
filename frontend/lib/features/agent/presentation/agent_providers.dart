import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../assistant/data/assistant_models.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../help/data/help_repository.dart';
import '../data/agent_repository.dart';
import '../data/appointment_reminders.dart';

/// Liste locale d'une collection de l'agent (sans les supprimés).
final agentListProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((
  ref,
  collection,
) async {
  final repo = await ref.watch(agentRepositoryProvider.future);
  final list = await repo.list(collection);
  String key(Map<String, dynamic> r) => '${r['visit_date'] ?? r['referral_date'] ?? ''}|${r['updated_at'] ?? ''}';
  return list..sort((a, b) => key(b).compareTo(key(a)));
});

final agentPendingProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = await ref.watch(agentRepositoryProvider.future);
  return repo.pendingCount();
});

/// Signes de danger servis par l'API (libellés français), gardés en cache pour la
/// liste à cocher des visites, même hors connexion.
final agentDangerSignsProvider = FutureProvider.autoDispose<List<DangerSign>>((ref) async {
  final repo = ref.watch(assistantRepositoryProvider);
  final cached = await repo.cachedDangerSigns('fr');
  if (cached.isNotEmpty) return cached;
  try {
    return await repo.fetchDangerSigns('fr');
  } catch (_) {
    return const [];
  }
});

/// « Rappels à faire » : rendez-vous en retard ou dans les 7 jours.
final agentRemindersProvider = FutureProvider.autoDispose<List<AppointmentReminder>>((ref) async {
  final repo = await ref.watch(agentRepositoryProvider.future);
  final beneficiaries = await repo.list(AgentCollections.beneficiaries);
  return dueAppointmentReminders(beneficiaries, DateTime.now(), phones: await repo.phones());
});

/// Numéros locaux des bénéficiaires (jamais synchronisés).
final agentPhonesProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final repo = await ref.watch(agentRepositoryProvider.future);
  return repo.phones();
});

/// Services de santé et d'urgence de l'annuaire EN CACHE, pour la fiche
/// d'aide à la décision (aucun numéro écrit dans l'application).
const decisionAidCategories = {'health', 'emergency'};

final agentHelpServicesProvider = FutureProvider.autoDispose<List<HelpService>>((ref) async {
  final cached = await ref.watch(helpRepositoryProvider).cachedServices();
  final services = (cached?.$1 ?? const <HelpService>[])
      .where((s) => decisionAidCategories.contains(s.category))
      .toList();
  // Urgences d'abord, puis les numéros vérifiés.
  services.sort((a, b) {
    final byCategory = (a.category == 'emergency' ? 0 : 1) - (b.category == 'emergency' ? 0 : 1);
    return byCategory != 0 ? byCategory : (b.verified ? 1 : 0) - (a.verified ? 1 : 0);
  });
  return services;
});

void refreshAgentLists(WidgetRef ref) {
  ref.invalidate(agentListProvider);
  ref.invalidate(agentPendingProvider);
  ref.invalidate(agentRemindersProvider);
  ref.invalidate(agentPhonesProvider);
}
