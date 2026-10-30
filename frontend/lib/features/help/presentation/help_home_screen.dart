import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/phone_actions.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../carnet/data/records.dart';
import '../../carnet/presentation/gentle_support.dart';
import '../../stats/stats_service.dart';
import 'help_gate.dart';

export 'help_gate.dart';

/// Page Aide (module 3) : alerte SOS, numéros utiles, journal privé, droits,
/// bien-être. Grand bouton « Sortie rapide » toujours visible en bas.
class HelpHomeScreen extends ConsumerStatefulWidget {
  const HelpHomeScreen({super.key});

  @override
  ConsumerState<HelpHomeScreen> createState() => _HelpHomeScreenState();
}

class _HelpHomeScreenState extends ConsumerState<HelpHomeScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(statsServiceProvider).track(StatEvent.helpOpened);
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, Color color, String path) =>
        PictoTile(icon: icon, label: label, color: color, listenText: label, onTap: () => context.push(path));

    return HelpGate(
      child: LaafiScaffold(
        title: S.helpTitle,
        listenText: S.helpListen,
        protectedArea: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SosButton(),
            const SizedBox(height: AppSpacing.md),
            TileGrid(
              children: [
                tile(Icons.phone_in_talk_rounded, S.directory, AppTheme.leaf, '/help/directory'),
                tile(Icons.edit_note_rounded, S.journal, AppTheme.plum, '/help/journal'),
                tile(Icons.gavel_rounded, S.rights, AppTheme.sky, '/help/rights'),
                tile(Icons.air_rounded, S.breathing, AppTheme.leaf, '/help/breathing'),
                tile(
                  Icons.hearing_rounded,
                  S.listeningServices,
                  AppTheme.terracotta,
                  '/help/directory?filter=listening',
                ),
                tile(Icons.people_alt_rounded, S.trustedContacts, AppTheme.amber, '/help/contacts'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton d'alerte : un APPUI LONG lance un compte à rebours de 5 s
/// annulable, puis ouvre l'application SMS avec le message prêt. Ensuite,
/// une feuille propose de parler à quelqu'un ou de respirer.
class SosButton extends ConsumerWidget {
  const SosButton({super.key});

  Future<void> _start(BuildContext context) async {
    final prepared = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SosCountdownDialog(),
    );
    if (prepared == true && context.mounted) await showSupportSheet(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Moins de 18 ans : jamais de position dans le message (voir le dialogue).
    final minor = ref.watch(isMinorProvider).valueOrNull ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: '${S.sos}. ${S.sosHint}',
          child: Material(
            color: AppTheme.danger,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              onTap: () => showSnack(context, S.sosHint),
              onLongPress: () => _start(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Column(
                  children: [
                    const Icon(Icons.sos_rounded, size: 72, color: Colors.white),
                    Text(S.sos, style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
                    Text(S.sosHint, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(child: Text(S.sosHonest, style: theme.textTheme.bodyMedium)),
            const ListenButton(text: S.sosHonest, compact: true),
          ],
        ),
        if (minor) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.location_off_rounded),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(S.sosNoLocationMinor, style: theme.textTheme.bodyMedium)),
              const ListenButton(text: S.sosNoLocationMinor, compact: true),
            ],
          ),
        ],
      ],
    );
  }
}

/// Position actuelle si la femme l'autorise ; `null` sinon (jamais bloquant).
Future<Position?> currentPositionIfAllowed() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
  } catch (_) {
    return null;
  }
}

String buildSosMessage(String base, Position? position) {
  if (position == null) return base;
  final lat = position.latitude.toStringAsFixed(5);
  final lng = position.longitude.toStringAsFixed(5);
  return '$base ${S.sosLocation} : https://maps.google.com/?q=$lat,$lng';
}

class SosCountdownDialog extends ConsumerStatefulWidget {
  const SosCountdownDialog({super.key});

  @override
  ConsumerState<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends ConsumerState<SosCountdownDialog> {
  static const _seconds = 5;
  int _left = _seconds;
  Timer? _timer;

  /// Mineure : la position n'est même pas demandée au téléphone.
  late final Future<Position?> _position = _positionUnlessMinor();
  late final Future<List<Map<String, dynamic>>> _contacts = ref.read(collectionProvider(Col.contacts).future);
  bool _noContacts = false;

  @override
  void initState() {
    super.initState();
    _contacts.then((list) {
      if (list.isEmpty && mounted) {
        _timer?.cancel();
        setState(() => _noContacts = true);
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        timer.cancel();
        _send();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Position?> _positionUnlessMinor() async {
    final minor = await ref.read(isMinorProvider.future).catchError((Object _) => false);
    return minor ? null : currentPositionIfAllowed();
  }

  Future<void> _send() async {
    final contacts = await _contacts;
    if (contacts.isEmpty) return;
    final base = ref.read(settingsProvider).sosMessage ?? S.sosDefaultMessage;
    final position = await _position.timeout(const Duration(seconds: 3), onTimeout: () => null);
    await ref.read(statsServiceProvider).track(StatEvent.helpAlertSent);
    await openSmsComposer([for (final c in contacts.take(3)) c['phone'].toString()], buildSosMessage(base, position));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: AppTheme.danger,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_noContacts) ...[
            Text(S.sosNoContacts, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.danger),
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/help/contacts');
              },
              child: const Text(S.trustedContacts),
            ),
          ] else ...[
            Text(
              _left > 0 ? S.sosCountdown(_left) : S.sending,
              style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(S.sosHonest, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.danger,
                minimumSize: const Size.fromHeight(64),
              ),
              onPressed: () {
                _timer?.cancel();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close_rounded, size: 32),
              label: const Text(S.cancel, style: TextStyle(fontSize: 22)),
            ),
          ),
        ],
      ),
    );
  }
}
