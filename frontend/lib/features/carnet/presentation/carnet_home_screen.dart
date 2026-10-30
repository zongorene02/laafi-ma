import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/security/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../learn/presentation/weekly_tip_card.dart';
import '../data/records.dart';
import '../records/record_screens.dart';
import 'gentle_support.dart';

/// Sommaire du carnet de santé (tout reste sur le téléphone, chiffré).
class CarnetHomeScreen extends ConsumerWidget {
  const CarnetHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(settingsProvider.select((s) => s.consentRecord));
    final isDecoy = ref.watch(sessionProvider.select((s) => s.isDecoy));
    final profile = ref.watch(sessionProvider.select((s) => s.profileIndex));
    final lowMood = ref.watch(lowMoodStreakProvider);

    if (!consent) {
      return LaafiScaffold(
        title: S.carnetTitle,
        listenText: '${S.consentRecordTitle}. ${S.consentRecordText}',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_person_rounded, size: 80),
            const SizedBox(height: AppSpacing.md),
            Text(S.consentRecordTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            Text(S.consentRecordText, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            const Center(child: ListenButton(text: '${S.consentRecordTitle}. ${S.consentRecordText}')),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(consentRecord: true)),
              icon: const Icon(Icons.thumb_up_alt_rounded),
              label: const Text(S.accept),
            ),
          ],
        ),
      );
    }

    PictoTile tile(IconData icon, String label, Color color, String path) =>
        PictoTile(icon: icon, label: label, color: color, listenText: label, onTap: () => context.push(path));

    return LaafiScaffold(
      title: S.carnetTitle,
      listenText: S.carnetListen,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lowMood) ...[const GentleSupportCard(), const SizedBox(height: AppSpacing.sm)],
          const WeeklyTipCard(),
          TileGrid(
            minTileWidth: 150,
            children: [
              tile(Icons.person_rounded, S.healthProfile, AppTheme.sky, '/carnet/single/${Col.healthProfile}'),
              tile(Icons.water_drop_rounded, S.cycle, AppTheme.danger, recordListPath(Col.cycles)),
              tile(Icons.medication_liquid_rounded, S.contraception, AppTheme.plum, recordListPath(Col.contraception)),
              tile(Icons.pregnant_woman_rounded, S.pregnancy, AppTheme.terracotta, '/carnet/pregnancy'),
              tile(Icons.child_friendly_rounded, S.postpartum, AppTheme.amber, '/carnet/postpartum'),
              tile(Icons.child_care_rounded, S.children, AppTheme.amber, recordListPath(Col.children)),
              tile(Icons.medical_services_rounded, S.consultations, AppTheme.sky, recordListPath(Col.consultations)),
              tile(Icons.photo_library_rounded, S.documents, AppTheme.leaf, '/carnet/documents'),
              tile(Icons.medication_rounded, S.medicines, AppTheme.plum, recordListPath(Col.medicines)),
              tile(Icons.calendar_month_rounded, S.agenda, AppTheme.leaf, '/carnet/agenda'),
              tile(Icons.self_improvement_rounded, S.wellbeing, AppTheme.leaf, '/carnet/wellbeing'),
              tile(Icons.qr_code_2_rounded, S.share, AppTheme.terracotta, '/carnet/share'),
              // Le profil leurre n'a pas de sauvegarde en ligne. Téléphone partagé :
              // le compte de sauvegarde est celui du téléphone, donc du profil 1.
              if (!isDecoy && profile == 1) tile(Icons.cloud_upload_rounded, S.backup, AppTheme.sky, '/carnet/backup'),
            ],
          ),
        ],
      ),
    );
  }
}
