import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../data/backup_service.dart';
import '../data/records.dart';
import '../domain/backup_crypto.dart';

final _accountProvider = FutureProvider.autoDispose<(DeviceAccount?, String?)>((ref) async {
  final service = ref.watch(backupServiceProvider);
  return (await service.account(), await service.lastBackupAt());
});

/// Sauvegarde chiffrée facultative (nécessite internet).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _accountId = TextEditingController();
  final _recovery = TextEditingController();
  bool _includeMedia = true;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    for (final c in [_pass, _pass2, _accountId, _recovery]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      setState(() {
        _message = message;
        _messageIsError = false;
      });
    } on BackupDecryptException {
      setState(() {
        _message = S.wrongPassphrase;
        _messageIsError = true;
      });
    } catch (e) {
      setState(() {
        _message = e.toString();
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(_accountProvider);
    }
  }

  Future<void> _showRecovery(DeviceAccount account) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 48),
        title: const Text(S.recoveryCodeTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.recoveryCodeWarning, style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.danger)),
              const SizedBox(height: AppSpacing.md),
              const Text(S.accountId),
              SelectableText(account.accountId, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              const Text(S.recoveryCode),
              SelectableText(
                account.recoveryCode,
                style: theme.textTheme.headlineSmall?.copyWith(fontFamily: 'monospace', letterSpacing: 2),
              ),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text(S.iWroteItDown))],
      );
    },
  );

  String? _checkPassphrase({bool confirm = true}) {
    if (_pass.text.length < 8) return S.passphraseTooShort;
    if (confirm && _pass.text != _pass2.text) return S.pinMismatch;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(settingsProvider.select((s) => s.consentBackup));
    final accountState = ref.watch(_accountProvider);
    final service = ref.read(backupServiceProvider);
    final theme = Theme.of(context);

    final passFields = [
      TextField(
        controller: _pass,
        obscureText: true,
        decoration: const InputDecoration(labelText: S.passphrase, prefixIcon: Icon(Icons.key_rounded)),
      ),
      const SizedBox(height: AppSpacing.sm),
    ];

    return LaafiScaffold(
      title: S.backup,
      listenText: S.backupListen,
      backTo: '/carnet',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(text: S.backupListen, icon: Icons.lock_rounded),
          const SizedBox(height: AppSpacing.md),
          if (!consent) ...[
            const InfoBanner(text: S.backupDisabledByConsent),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(consentBackup: true)),
              child: const Text(S.accept),
            ),
          ] else
            accountState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(message: e.toString()),
              data: (data) {
                final (account, last) = data;
                if (account == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final created = await service.createAccount();
                                if (mounted) await _showRecovery(created);
                                return null;
                              }),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text(S.createAccount),
                      ),
                      const SectionTitle(S.restoreFromOtherPhone),
                      TextField(
                        controller: _accountId,
                        decoration: const InputDecoration(labelText: S.accountId),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _recovery,
                        decoration: const InputDecoration(labelText: S.recoveryCode, hintText: 'XXXX-XXXX-XXXX-XXXX'),
                        inputFormatters: [UpperCaseTextFormatter()],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...passFields,
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final error = _checkPassphrase(confirm: false);
                                if (error != null) throw Exception(error);
                                await service.attachAccount(
                                  DeviceAccount(accountId: _accountId.text.trim(), recoveryCode: _recovery.text.trim()),
                                );
                                await service.restore(_pass.text);
                                _invalidateCarnet();
                                return S.restoreDone;
                              }),
                        icon: const Icon(Icons.cloud_download_rounded),
                        label: const Text(S.restore),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${S.lastBackup} : ${last == null ? S.notSet : '${frDate(parseTimestamp(last)?.toLocal())} ${hhmm(parseTimestamp(last)!.toLocal())}'}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ...passFields,
                    TextField(
                      controller: _pass2,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: S.passphraseConfirm),
                    ),
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: SwitchListTile(
                        title: const Text(S.includeMedia),
                        value: _includeMedia,
                        onChanged: (v) => setState(() => _includeMedia = v),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final error = _checkPassphrase();
                              if (error != null) throw Exception(error);
                              await service.backup(_pass.text, includeMedia: _includeMedia);
                              await trackBackup(ref);
                              return S.backupDone;
                            }),
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text(S.backupNow),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final error = _checkPassphrase(confirm: false);
                              if (error != null) throw Exception(error);
                              if (!await confirmDialog(context, '${S.restore} ?', confirmLabel: S.restore)) return null;
                              await service.restore(_pass.text);
                              _invalidateCarnet();
                              return S.restoreDone;
                            }),
                      icon: const Icon(Icons.cloud_download_rounded),
                      label: const Text(S.restore),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              if (!await confirmDialog(context, '${S.deleteBackup} ?')) return null;
                              await service.deleteRemote();
                              return S.deleteBackup;
                            }),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text(S.deleteBackup),
                    ),
                  ],
                );
              },
            ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.xs),
            const Text(S.loading, textAlign: TextAlign.center),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBanner(
              text: _message!.replaceFirst('Exception: ', ''),
              color: _messageIsError ? theme.colorScheme.error : AppTheme.leaf,
              icon: _messageIsError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            ),
          ],
        ],
      ),
    );
  }

  void _invalidateCarnet() => ref.invalidate(collectionProvider);
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
