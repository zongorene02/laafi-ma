import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/l10n/strings.dart';
import 'core/providers.dart';
import 'core/security/pin_flags.dart';
import 'core/security/pin_service.dart';
import 'core/storage/secret_store.dart';
import 'core/storage/vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter('laafi_ma');
  runApp(const AppRoot());
}

/// Ouvre les coffres nécessaires AVANT la première image : réglages globaux
/// (calculatrice ou écran du code ? quelle langue ?) et cache public.
Future<List<Override>> bootstrap() async {
  final secrets = SecureSecretStore();
  final vault = VaultService(secrets);
  final meta = await vault.open(VaultName.meta);
  final cache = await vault.open(VaultName.cache);
  final settings = await SettingsController.load(meta);
  final flags = await PinFlagsController.load(PinService(secrets));
  return [
    secretStoreProvider.overrideWithValue(secrets),
    vaultProvider.overrideWithValue(vault),
    metaStoreProvider.overrideWithValue(meta),
    cacheStoreProvider.overrideWithValue(cache),
    initialSettingsProvider.overrideWithValue(settings),
    initialPinFlagsProvider.overrideWithValue(flags),
  ];
}

/// Racine redémarrable : après « Supprimer toutes mes données », tout l'état
/// (providers, coffres ouverts) est reconstruit de zéro.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  /// Fonction de redémarrage, à récupérer AVANT de démonter l'écran appelant.
  static VoidCallback? restarter(BuildContext context) => context.findAncestorStateOfType<_AppRootState>()?._restart;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  Key _key = UniqueKey();
  late Future<List<Override>> _boot = bootstrap();

  void _restart() => setState(() {
    _key = UniqueKey();
    _boot = bootstrap();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Override>>(
      key: _key,
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('${S.appName} ne peut pas démarrer : ${snapshot.error}', textAlign: TextAlign.center),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return ProviderScope(key: _key, overrides: snapshot.data!, child: const LaafiApp());
      },
    );
  }
}
