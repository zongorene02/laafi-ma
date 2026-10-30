import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/languages.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/security/icon_disguise.dart';
import '../../../core/security/pin_flags.dart';
import '../../../core/security/pin_service.dart';
import '../../../core/security/session.dart';
import '../../../core/storage/cache.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../carnet/data/backup_service.dart';
import '../../carnet/data/reminder_service.dart';
import '../../stats/stats_service.dart';
import 'profiles_card.dart';

class District {
  const District({required this.id, required this.name, this.region});

  factory District.fromJson(Map<String, dynamic> json) =>
      District(id: json['id'] as String, name: json['name'] as String? ?? '', region: json['region'] as String?);

  final String id;
  final String name;
  final String? region;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'region': region};
}

/// `GET /districts` (liste réelle saisie par un administrateur ; peut être
/// vide). Gardée en cache pour l'affichage hors connexion.
Future<List<District>> fetchDistricts(Dio dio, {required Future<void> Function(Object) saveCache}) async {
  try {
    final response = await dio.get('/districts');
    final list = [for (final d in response.data as List) District.fromJson((d as Map).cast<String, dynamic>())];
    await saveCache(list.map((d) => d.toJson()).toList());
    return list;
  } on DioException catch (e) {
    throw ApiClient.toApiException(e);
  }
}

final districtsProvider = FutureProvider.autoDispose<List<District>>((ref) async {
  final cache = ref.watch(cacheStoreProvider);
  try {
    return await fetchDistricts(
      ref.watch(dioProvider),
      saveCache: (data) => writeCache(cache, 'districts', 'all', data),
    );
  } catch (_) {
    final cached = await readCache(cache, 'districts', 'all');
    final data = cached?.data;
    if (data is List) return [for (final d in data) District.fromJson((d as Map).cast<String, dynamic>())];
    rethrow;
  }
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _editSosMessage(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: ref.read(settingsProvider).sosMessage ?? S.sosDefaultMessage);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.sosMessage),
        content: TextField(controller: controller, minLines: 3, maxLines: 6),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text(S.save)),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty) {
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(sosMessage: result));
    }
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    if (!await confirmDialog(context, S.wipeConfirm, confirmLabel: S.wipeAll)) return;
    var remoteFailed = false;
    final backup = ref.read(backupServiceProvider);
    if (await backup.account() != null) {
      try {
        await backup.deleteAccount();
      } catch (_) {
        remoteFailed = true;
      }
    }
    if (remoteFailed && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: const Text(S.wipeOfflineWarning),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text(S.ok))],
        ),
      );
    }
    if (!context.mounted) return;
    final restart = AppRoot.restarter(context);
    await ref.read(reminderServiceProvider).cancelAll();
    // L'icône « Calculatrice » ne doit pas survivre à l'effacement.
    if (ref.read(settingsProvider).iconDisguise) await ref.read(iconDisguiseProvider).setDisguised(false);
    final vault = ref.read(vaultProvider);
    ref.read(sessionProvider.notifier).lock();
    await vault.wipeAll();
    restart?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final flags = ref.watch(pinFlagsProvider);
    final isDecoy = ref.watch(sessionProvider.select((s) => s.isDecoy));
    final profile = ref.watch(sessionProvider.select((s) => s.profileIndex));
    // Réglages valables pour tout le téléphone : seulement dans le profil 1.
    final deviceOwner = !isDecoy && profile == 1;
    final iconDisguise = ref.watch(iconDisguiseProvider);
    final districts = ref.watch(districtsProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    final pins = ref.read(pinServiceProvider);

    Widget card(List<Widget> children) => Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(children: children),
    );

    Future<void> removeCode(PinSlot slot) async {
      if (!await confirmDialog(context, '${S.remove} ?', confirmLabel: S.remove)) return;
      await pins.clear(slot);
      await ref.read(pinFlagsProvider.notifier).refresh();
    }

    return LaafiScaffold(
      title: S.settings,
      listenText: S.settingsListen,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(S.language),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final lang in kSupportedLanguages)
                ChoiceChip(
                  label: Text(lang.name, style: theme.textTheme.titleMedium),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  selected: settings.lang == lang.code,
                  onSelected: (_) => notifier.update((s) => s.copyWith(lang: lang.code)),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(S.onbLangNote),
          ),
          if (!isDecoy) ...[
            const SectionTitle(S.security),
            card([
              ListTile(
                leading: const Icon(Icons.pin_rounded),
                title: const Text(S.changePin),
                onTap: () => context.push('/settings/pin/${PhoneProfiles.pinSlot(profile).name}'),
              ),
              if (deviceOwner)
                ListTile(
                  leading: const Icon(Icons.theater_comedy_rounded),
                  title: const Text(S.decoyPin),
                  subtitle: const Text(S.decoyText),
                  trailing: flags.hasDecoy
                      ? TextButton(onPressed: () => removeCode(PinSlot.decoy), child: const Text(S.remove))
                      : null,
                  onTap: () => context.push('/settings/pin/${PinSlot.decoy.name}'),
                ),
              ListTile(
                leading: const Icon(Icons.shield_rounded),
                title: const Text(S.helpCode),
                subtitle: const Text(S.helpCodeText),
                trailing: flags.hasHelpCodeFor(profile)
                    ? TextButton(
                        onPressed: () => removeCode(PhoneProfiles.helpSlot(profile)),
                        child: const Text(S.remove),
                      )
                    : null,
                onTap: () => context.push('/settings/pin/${PhoneProfiles.helpSlot(profile).name}'),
              ),
              const HelpPhraseTile(),
              if (deviceOwner) ...[
                SwitchListTile(
                  secondary: const Icon(Icons.calculate_rounded),
                  title: const Text(S.disguise),
                  subtitle: const Text(S.disguiseText),
                  value: settings.disguise,
                  onChanged: (v) => notifier.update((s) => s.copyWith(disguise: v)),
                ),
                // Android seulement : caché sur le web et ailleurs.
                if (iconDisguise.supported)
                  SwitchListTile(
                    secondary: const Icon(Icons.apps_rounded),
                    title: const Text(S.iconDisguise),
                    subtitle: const Text(S.iconDisguiseText),
                    value: settings.iconDisguise,
                    onChanged: (v) async {
                      if (!await iconDisguise.setDisguised(v)) {
                        if (context.mounted) showSnack(context, S.iconDisguiseFailed);
                        return;
                      }
                      await notifier.update((s) => s.copyWith(iconDisguise: v));
                    },
                  ),
              ],
            ]),
            const ProfilesCard(),
            if (!deviceOwner) const InfoBanner(text: S.deviceSettingsProfile1),
          ],
          const SectionTitle(S.tileHelp),
          card([
            ListTile(
              leading: const Icon(Icons.people_alt_rounded),
              title: const Text(S.trustedContacts),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/help/contacts'),
            ),
            ListTile(
              leading: const Icon(Icons.sms_rounded),
              title: const Text(S.sosMessage),
              subtitle: Text(settings.sosMessage ?? S.sosDefaultMessage),
              onTap: () => _editSosMessage(context, ref),
            ),
          ]),
          const SectionTitle(S.district),
          districts.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(e.toString()),
            data: (list) => DropdownButtonFormField<String?>(
              initialValue: list.any((d) => d.id == settings.districtId) ? settings.districtId : null,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.map_rounded)),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text(S.noDistrict)),
                for (final d in list)
                  DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text(d.region == null ? d.name : '${d.name} (${d.region})'),
                  ),
              ],
              onChanged: (v) =>
                  notifier.update((s) => v == null ? s.copyWith(clearDistrict: true) : s.copyWith(districtId: v)),
            ),
          ),
          const SectionTitle(S.stats),
          card([
            SwitchListTile(
              title: const Text(S.consentStatsTitle),
              subtitle: const Text(S.consentStatsText),
              value: settings.statsOptIn,
              onChanged: (v) async {
                await notifier.update((s) => s.copyWith(statsOptIn: v));
                // Refus : la file d'attente locale est vidée tout de suite.
                await ref.read(statsServiceProvider).flush();
              },
            ),
            SwitchListTile(
              title: const Text(S.consentRecord),
              value: settings.consentRecord,
              onChanged: (v) => notifier.update((s) => s.copyWith(consentRecord: v)),
            ),
          ]),
          if (deviceOwner) ...[
            card([
              ListTile(
                leading: const Icon(Icons.cloud_upload_rounded),
                title: const Text(S.backup),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/carnet/backup'),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
              onPressed: () => _wipe(context, ref),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text(S.wipeAll),
            ),
          ],
        ],
      ),
    );
  }
}
