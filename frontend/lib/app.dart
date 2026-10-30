import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/strings.dart';
import 'core/router/app_router.dart';
import 'core/security/session.dart';
import 'core/theme/app_theme.dart';
import 'features/stats/stats_service.dart';

class LaafiApp extends ConsumerStatefulWidget {
  const LaafiApp({super.key});

  @override
  ConsumerState<LaafiApp> createState() => _LaafiAppState();
}

class _LaafiAppState extends ConsumerState<LaafiApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Verrouillage automatique dès que l'application passe en arrière-plan
    // (bouton accueil, appel entrant, onglet masqué sur le web).
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
          ref.read(sessionProvider.notifier).onBackground();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stats = ref.read(statsServiceProvider);
      stats.track(StatEvent.appOpened);
      stats.trackMonthlyActive();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('fr')],
      locale: const Locale('fr'),
    );
  }
}
