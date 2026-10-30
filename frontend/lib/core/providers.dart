import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/data/translation_api.dart';
import 'network/api_client.dart';
import 'security/pin_service.dart';
import 'settings/app_settings.dart';
import 'storage/json_store.dart';
import 'storage/secret_store.dart';
import 'storage/token_storage.dart';
import 'storage/vault.dart';

/// Providers racine. Les coffres `meta` et `cache` sont ouverts AVANT le
/// lancement de l'interface (voir `main.dart`) et injectés par `overrides` ;
/// les tests y mettent des [MemoryJsonStore].
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

final vaultProvider = Provider<VaultService>((ref) => VaultService(ref.watch(secretStoreProvider)));

final metaStoreProvider = Provider<JsonStore>((ref) => throw UnimplementedError('metaStoreProvider non initialisé'));

final cacheStoreProvider = Provider<JsonStore>((ref) => throw UnimplementedError('cacheStoreProvider non initialisé'));

/// Réglages lus au démarrage, avant la première image.
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage(ref.watch(secretStoreProvider)));

final pinServiceProvider = Provider<PinService>((ref) => PinService(ref.watch(secretStoreProvider)));

/// Incrémenté quand le serveur rejette le jeton d'un agent : la session agent
/// (voir `agent_session.dart`) l'observe et redemande la connexion.
final staffAuthVersionProvider = StateProvider<int>((ref) => 0);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(tokenStorageProvider),
    onStaffUnauthorized: () => ref.read(staffAuthVersionProvider.notifier).state++,
  ),
);

final dioProvider = Provider<Dio>((ref) => ref.watch(apiClientProvider).dio);

final translationApiProvider = Provider<TranslationApi>((ref) => TranslationApi(ref.watch(dioProvider)));

class SettingsController extends Notifier<AppSettings> {
  static const collection = 'settings';
  static const docId = 'app';

  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    state = change(state);
    await ref.read(metaStoreProvider).put(collection, docId, state.toJson());
  }

  static Future<AppSettings> load(JsonStore meta) async {
    final json = await meta.get(collection, docId);
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Langue des contenus et de la voix (fr, mos, dyu).
final langProvider = Provider<String>((ref) => ref.watch(settingsProvider.select((s) => s.lang)));
