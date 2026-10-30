// Parcours de bout en bout de l'interface, avec des coffres en mémoire (le
// vrai stockage sécurisé et Hive n'existent pas dans l'environnement de test).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:laafi_ma/app.dart';
import 'package:laafi_ma/core/l10n/strings.dart';
import 'package:laafi_ma/core/providers.dart';
import 'package:laafi_ma/core/security/icon_disguise.dart';
import 'package:laafi_ma/core/security/pin_service.dart';
import 'package:laafi_ma/core/settings/app_settings.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/core/storage/secret_store.dart';
import 'package:laafi_ma/core/storage/vault.dart';
import 'package:laafi_ma/features/stats/stats_service.dart';

import 'helpers/fake_http.dart';

/// Doublure du changement d'icône (le vrai passe par un canal Android).
class _FakeIconDisguise implements IconDisguise {
  _FakeIconDisguise({required this.supported});

  @override
  final bool supported;
  final List<bool> calls = [];

  @override
  Future<bool> setDisguised(bool disguised) async {
    calls.add(disguised);
    return true;
  }
}

class _Harness {
  _Harness({this._settings = const AppSettings(), bool iconSupported = false})
    : icon = _FakeIconDisguise(supported: iconSupported);

  final AppSettings _settings;
  final _FakeIconDisguise icon;
  final secrets = MemorySecretStore();
  final stores = <String, MemoryJsonStore>{};

  late final pins = PinService(secrets, iterations: 1000);

  Widget build() {
    final vault = VaultService(
      secrets,
      opener: (name, key) async => stores.putIfAbsent(name, MemoryJsonStore.new),
      deleter: (name) async => stores.remove(name),
    );
    final offline = fakeApi((_) => emptyResponse(503));
    return ProviderScope(
      overrides: [
        secretStoreProvider.overrideWithValue(secrets),
        vaultProvider.overrideWithValue(vault),
        metaStoreProvider.overrideWithValue(stores.putIfAbsent(VaultName.meta, MemoryJsonStore.new)),
        cacheStoreProvider.overrideWithValue(stores.putIfAbsent(VaultName.cache, MemoryJsonStore.new)),
        initialSettingsProvider.overrideWithValue(_settings),
        pinServiceProvider.overrideWithValue(pins),
        iconDisguiseProvider.overrideWithValue(icon),
        apiClientProvider.overrideWithValue(offline.client),
        statsServiceProvider.overrideWith(
          (ref) => StatsService(
            dio: offline.client.dio,
            queue: MemoryJsonStore(),
            optedIn: () => false,
            lang: () => 'fr',
            districtId: () => null,
          ),
        ),
      ],
      child: const LaafiApp(),
    );
  }
}

Future<void> _tapKeys(WidgetTester tester, String keys) async {
  for (final key in keys.split(' ')) {
    await tester.tap(find.widgetWithText(FilledButton, key).last);
    await tester.pump();
  }
}

void main() {
  testWidgets('premier lancement : choix de la langue', (tester) async {
    await tester.pumpWidget(_Harness().build());
    await tester.pumpAndSettle();
    expect(find.text(S.onbChooseLang), findsOneWidget);
    expect(find.text('Mooré'), findsOneWidget);
    expect(find.text('Dioula'), findsOneWidget);
  });

  testWidgets('camouflage : calculatrice, puis code + « = » ouvre l\'accueil, sortie rapide referme', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final harness = _Harness(settings: const AppSettings(onboarded: true, disguise: true, consentRecord: true));
    await harness.pins.set(PinSlot.real, '4821');
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // Une vraie calculatrice.
    await _tapKeys(tester, '1 2 + 3 0 =');
    expect(find.text('42'), findsOneWidget);
    expect(find.text(S.tileAssistant), findsNothing);

    // Mauvais code : rien ne trahit l'existence d'un code.
    await _tapKeys(tester, '1 1 1 1 =');
    await tester.pumpAndSettle();
    expect(find.text(S.tileAssistant), findsNothing);
    expect(find.text(S.wrongPin), findsNothing);

    await _tapKeys(tester, '4 8 2 1 =');
    await tester.pumpAndSettle();
    expect(find.text(S.tileAssistant), findsOneWidget);
    expect(find.text(S.tileCarnet), findsOneWidget);
    expect(find.text(S.tileHelp), findsOneWidget);
    expect(find.text(S.tileLearn), findsOneWidget);
    expect(find.text(S.tileAgent), findsOneWidget);

    await tester.tap(find.byTooltip(S.quickExit));
    await tester.pumpAndSettle();
    expect(find.text(S.tileAssistant), findsNothing);
    expect(find.text('÷'), findsOneWidget);
  });

  testWidgets('code leurre : ouvre un carnet vide, séparé du vrai', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final harness = _Harness(settings: const AppSettings(onboarded: true, consentRecord: true));
    await harness.pins.set(PinSlot.real, '4821');
    await harness.pins.set(PinSlot.decoy, '2580');
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(find.text(S.lockTitle), findsOneWidget);

    Future<void> enter(String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.widgetWithText(FilledButton, d));
        await tester.pump();
      }
      await tester.tap(find.bySemanticsLabel(S.ok));
      await tester.pumpAndSettle();
    }

    await enter('2580');
    expect(find.text(S.tileCarnet), findsOneWidget);
    expect(harness.stores.containsKey(VaultName.decoy), isTrue);
    expect(harness.stores.containsKey(VaultName.real), isFalse);
  });

  testWidgets("chaque écran s'affiche sans débordement à largeur de téléphone (hors connexion)", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final harness = _Harness(settings: const AppSettings(onboarded: true, consentRecord: true, consentBackup: true));
    await harness.pins.set(PinSlot.real, '4821');
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    for (final d in '4821'.split('')) {
      await tester.tap(find.widgetWithText(FilledButton, d));
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel(S.ok));
    await tester.pumpAndSettle();
    expect(find.text(S.tileCarnet), findsOneWidget);

    const routes = [
      '/carnet',
      '/carnet/single/health_profile',
      '/carnet/r/cycles',
      '/carnet/r/consultations/edit',
      '/carnet/r/medicines/edit',
      '/carnet/pregnancy',
      '/carnet/postpartum',
      '/carnet/documents',
      '/carnet/agenda',
      '/carnet/wellbeing',
      '/carnet/share',
      '/carnet/backup',
      '/assistant/faq',
      '/help',
      '/help/directory',
      '/help/journal',
      '/help/breathing',
      '/help/contacts',
      '/learn',
      '/agent',
      '/assistant',
      '/agent/decision',
      '/settings',
      '/settings/pin/decoy',
      '/settings/pin/real2',
    ];
    for (final route in routes) {
      final context = tester.element(find.byType(Scaffold).last);
      GoRouter.of(context).go(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: route);
      expect(find.byTooltip(S.quickExit), findsWidgets, reason: route);
    }
  });

  profileTests();
}

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.widgetWithText(FilledButton, d));
    await tester.pump();
  }
  await tester.tap(find.bySemanticsLabel(S.ok));
  await tester.pumpAndSettle();
}

void profileTests() {
  testWidgets('téléphone partagé : le code du profil 2 ouvre SON coffre', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final harness = _Harness(settings: const AppSettings(onboarded: true, consentRecord: true));
    await harness.pins.set(PinSlot.real, '4821');
    await harness.pins.set(PinSlot.real2, '1357');
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await _enterPin(tester, '1357');
    expect(find.text(S.tileCarnet), findsOneWidget);
    expect(harness.stores.containsKey(VaultName.profile(2)), isTrue);
    expect(harness.stores.containsKey(VaultName.real), isFalse);
  });

  testWidgets('réglages : « Changer aussi l\'icône » seulement si le téléphone le permet', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    for (final supported in [false, true]) {
      final harness = _Harness(
        settings: const AppSettings(onboarded: true, consentRecord: true),
        iconSupported: supported,
      );
      await harness.pins.set(PinSlot.real, '4821');
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      await _enterPin(tester, '4821');
      GoRouter.of(tester.element(find.byType(Scaffold).last)).go('/settings');
      await tester.pumpAndSettle();
      expect(find.text(S.profilesTitle), findsOneWidget);
      expect(find.text(S.helpPhrase), findsOneWidget);
      expect(find.text(S.iconDisguise), supported ? findsOneWidget : findsNothing);
      if (supported) {
        await tester.ensureVisible(find.text(S.iconDisguise));
        await tester.tap(find.text(S.iconDisguise));
        await tester.pumpAndSettle();
        expect(harness.icon.calls, [true]);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
