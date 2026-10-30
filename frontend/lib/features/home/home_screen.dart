import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/languages.dart';
import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/laafi_scaffold.dart';
import '../../shared/widgets/listen_button.dart';
import '../../shared/widgets/page_layout.dart';

/// Accueil : cinq grandes tuiles pictogrammes, chacune avec son bouton
/// « Écouter ».
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(fit: BoxFit.scaleDown, child: BrandMark(size: 32)),
        actions: [
          IconButton(
            tooltip: S.settings,
            iconSize: 28,
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push('/settings'),
          ),
          const QuickExitAction(),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.formMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(S.onbWelcome, style: theme.textTheme.titleLarge)),
                    Chip(
                      avatar: const Icon(Icons.record_voice_over_rounded, size: 18),
                      label: Text(languageByCode(lang).name),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const ListenButton(text: S.homeListen, compact: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TileGrid(
                  aspectRatio: 0.9,
                  children: [
                    PictoTile(
                      big: true,
                      icon: Icons.mic_rounded,
                      label: S.tileAssistant,
                      color: AppTheme.terracotta,
                      listenText: S.tileAssistantListen,
                      onTap: () => context.push('/assistant'),
                    ),
                    PictoTile(
                      big: true,
                      icon: Icons.menu_book_rounded,
                      label: S.tileCarnet,
                      color: AppTheme.leaf,
                      listenText: S.tileCarnetListen,
                      onTap: () => context.push('/carnet'),
                    ),
                    PictoTile(
                      big: true,
                      icon: Icons.health_and_safety_rounded,
                      label: S.tileHelp,
                      color: AppTheme.danger,
                      listenText: S.tileHelpListen,
                      onTap: () => context.push('/help'),
                    ),
                    PictoTile(
                      big: true,
                      icon: Icons.school_rounded,
                      label: S.tileLearn,
                      color: AppTheme.sky,
                      listenText: S.tileLearnListen,
                      onTap: () => context.push('/learn'),
                    ),
                    PictoTile(
                      big: true,
                      icon: Icons.badge_rounded,
                      label: S.tileAgent,
                      color: AppTheme.plum,
                      listenText: S.tileAgentListen,
                      onTap: () => context.push('/agent'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
