import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agent/presentation/agent_home_screen.dart';
import '../../features/agent/presentation/beneficiary_screens.dart';
import '../../features/agent/presentation/decision_aid_screen.dart';
import '../../features/agent/presentation/gbv_screen.dart';
import '../../features/agent/presentation/scan_screen.dart';
import '../../features/agent/presentation/visit_form_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/assistant/presentation/faq_screen.dart';
import '../../features/carnet/presentation/agenda_screen.dart';
import '../../features/carnet/presentation/backup_screen.dart';
import '../../features/carnet/presentation/carnet_home_screen.dart';
import '../../features/carnet/presentation/cycle_header.dart';
import '../../features/carnet/presentation/documents_screen.dart';
import '../../features/carnet/presentation/postpartum_screen.dart';
import '../../features/carnet/presentation/pregnancy_screen.dart';
import '../../features/carnet/presentation/share_screen.dart';
import '../../features/carnet/presentation/wellbeing_screen.dart';
import '../../features/carnet/data/records.dart';
import '../../features/carnet/records/record_screens.dart';
import '../../features/help/presentation/breathing_screen.dart';
import '../../features/help/presentation/directory_screen.dart';
import '../../features/help/presentation/help_home_screen.dart';
import '../../features/help/presentation/journal_screens.dart';
import '../../features/home/home_screen.dart';
import '../../features/learn/presentation/learn_screens.dart';
import '../../features/lock/lock_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/settings/presentation/pin_setup_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/translate_text/presentation/translate_text_screen.dart';
import '../../features/translate_voice/presentation/translate_voice_screen.dart';
import '../../features/translate_voice_message/presentation/translate_voice_message_screen.dart';
import '../providers.dart';
import '../security/pin_service.dart';
import '../security/session.dart';

/// Relance la redirection dès que la session ou les réglages changent
/// (verrouillage, sortie rapide, fin de l'accueil).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(sessionProvider.select((s) => s.unlocked), (_, _) => notifyListeners());
    ref.listen(settingsProvider.select((s) => s.onboarded), (_, _) => notifyListeners());
  }
}

String? _q(GoRouterState state, String key) => state.uri.queryParameters[key];

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!ref.read(settingsProvider).onboarded) return location == '/onboarding' ? null : '/onboarding';
      if (!ref.read(sessionProvider).unlocked) return location == '/lock' ? null : '/lock';
      if (location == '/lock' || location == '/onboarding') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/lock', builder: (_, _) => const LockScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),

      // Module 1
      GoRoute(path: '/assistant', builder: (_, _) => const AssistantScreen()),
      GoRoute(path: '/assistant/faq', builder: (_, _) => const FaqScreen()),

      // Module 2
      GoRoute(path: '/carnet', builder: (_, _) => const CarnetHomeScreen()),
      GoRoute(
        path: '/carnet/single/:spec',
        builder: (_, state) => SingleRecordScreen(specId: state.pathParameters['spec']!),
      ),
      GoRoute(
        path: '/carnet/r/:spec',
        builder: (_, state) {
          final spec = state.pathParameters['spec']!;
          return RecordListScreen(
            specId: spec,
            parentId: _q(state, 'parent'),
            header: spec == Col.cycles ? const CycleHeader() : null,
          );
        },
      ),
      GoRoute(
        path: '/carnet/r/:spec/view',
        builder: (_, state) {
          final spec = state.pathParameters['spec']!;
          final id = _q(state, 'id')!;
          return RecordDetailScreen(
            specId: spec,
            id: id,
            footer: spec == Col.children ? ChildVaccinesButton(childId: id) : null,
          );
        },
      ),
      GoRoute(
        path: '/carnet/r/:spec/edit',
        builder: (_, state) => RecordFormScreen(
          specId: state.pathParameters['spec']!,
          id: _q(state, 'id'),
          parentId: _q(state, 'parent'),
          initial: state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : null,
        ),
      ),
      GoRoute(path: '/carnet/pregnancy', builder: (_, _) => const PregnancyScreen()),
      GoRoute(path: '/carnet/postpartum', builder: (_, _) => const PostpartumScreen()),
      GoRoute(path: '/carnet/documents', builder: (_, _) => const DocumentsScreen()),
      GoRoute(
        path: '/carnet/documents/view',
        builder: (_, state) => DocumentViewScreen(id: _q(state, 'id')!),
      ),
      GoRoute(path: '/carnet/agenda', builder: (_, _) => const AgendaWeekScreen()),
      GoRoute(path: '/carnet/wellbeing', builder: (_, _) => const WellbeingScreen()),
      GoRoute(path: '/carnet/share', builder: (_, _) => const ShareScreen()),
      GoRoute(path: '/carnet/backup', builder: (_, _) => const BackupScreen()),

      // Module 3 (tous derrière `HelpGate`, avec sortie rapide visible)
      GoRoute(path: '/help', builder: (_, _) => const HelpHomeScreen()),
      GoRoute(
        path: '/help/directory',
        builder: (_, state) => DirectoryScreen(listeningOnly: _q(state, 'filter') == 'listening'),
      ),
      GoRoute(path: '/help/journal', builder: (_, _) => const JournalScreen()),
      GoRoute(
        path: '/help/journal/edit',
        builder: (_, state) => JournalEntryScreen(id: _q(state, 'id')),
      ),
      GoRoute(
        path: '/help/rights',
        builder: (_, _) => const LearnHomeScreen(track: 'droits', protectedArea: true),
      ),
      GoRoute(path: '/help/breathing', builder: (_, _) => const BreathingScreen()),
      GoRoute(
        path: '/help/contacts',
        builder: (_, _) => const HelpGate(child: RecordListScreen(specId: Col.contacts, protectedArea: true)),
      ),

      // Module 5
      GoRoute(
        path: '/learn',
        builder: (_, state) => LearnHomeScreen(track: _q(state, 'track')),
      ),
      GoRoute(
        path: '/learn/capsule/:id',
        builder: (_, state) => CapsuleScreen(id: state.pathParameters['id']!),
      ),

      // Module 4 (tous derrière `AgentGate`)
      GoRoute(path: '/agent', builder: (_, _) => const AgentHomeScreen()),
      GoRoute(path: '/agent/beneficiaries', builder: (_, _) => const BeneficiariesScreen()),
      GoRoute(
        path: '/agent/beneficiary/edit',
        builder: (_, state) => BeneficiaryFormScreen(id: _q(state, 'id')),
      ),
      GoRoute(
        path: '/agent/beneficiary/view',
        builder: (_, state) => BeneficiaryDetailScreen(id: _q(state, 'id')!),
      ),
      GoRoute(
        path: '/agent/visit/edit',
        builder: (_, state) => VisitFormScreen(beneficiaryId: _q(state, 'beneficiary')!, id: _q(state, 'id')),
      ),
      GoRoute(path: '/agent/gbv', builder: (_, _) => const GbvReferralScreen()),
      GoRoute(
        path: '/agent/decision',
        builder: (_, state) => DecisionAidScreen(signId: _q(state, 'sign')),
      ),
      GoRoute(path: '/agent/scan', builder: (_, _) => const ScanQrScreen()),
      GoRoute(
        path: '/agent/translate/text',
        builder: (_, _) => const AgentGate(child: TranslateTextScreen()),
      ),
      GoRoute(
        path: '/agent/translate/voice',
        builder: (_, _) => const AgentGate(child: TranslateVoiceScreen()),
      ),
      GoRoute(
        path: '/agent/translate/message',
        builder: (_, _) => const AgentGate(child: TranslateVoiceMessageScreen()),
      ),

      // Réglages
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/pin/:slot',
        builder: (_, state) =>
            PinSetupScreen(slot: PinSlot.values.byName(state.pathParameters['slot']!), fromSettings: true),
      ),
    ],
  );
});
