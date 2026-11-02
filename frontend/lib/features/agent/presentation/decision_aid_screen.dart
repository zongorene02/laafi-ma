import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/data/phone_actions.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../../shared/widgets/listen_button.dart';
import '../../../shared/widgets/provisional_note.dart';
import '../../assistant/data/assistant_models.dart';
import '../../help/data/help_repository.dart';
import 'agent_gate.dart';
import 'agent_providers.dart';

String decisionAidPath(String signId) => Uri(path: '/agent/decision', queryParameters: {'sign': signId}).toString();

/// Texte lu par « Écouter » : la fiche telle qu'écrite, avec la mention
/// « pas encore relu » si aucune sage-femme ne l'a relue.
String decisionAidSpoken(DangerSign sign) {
  final text = !sign.hasDecisionAid
      ? '${sign.label}. ${sign.advice}. ${S.decisionAidNotWritten}'
      : [
          sign.label,
          if (sign.advice.isNotEmpty) '${S.adviceLabel} : ${sign.advice}',
          if (sign.agentQuestions.isNotEmpty) '${S.questionsToAsk} : ${sign.agentQuestions.join('. ')}',
          if (sign.referWhen != null) '${S.whenToRefer} : ${sign.referWhen}',
        ].join('. ');
  return withProvisionalNote(text, provisional: sign.provisional);
}

/// « Fiche d'aide à la décision » (module 4) : sans [signId], la liste des
/// signes de danger en cache ; avec, la fiche du signe. Tout vient des signes
/// servis par l'API ; rien n'est rédigé dans l'application.
class DecisionAidScreen extends ConsumerWidget {
  const DecisionAidScreen({super.key, this.signId});

  final String? signId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signs = ref.watch(agentDangerSignsProvider);
    final sign = signId == null ? null : signs.valueOrNull?.where((s) => s.id == signId).firstOrNull;
    return AgentGate(
      child: LaafiScaffold(
        title: sign?.label ?? S.decisionAid,
        listenText: sign == null ? S.decisionAidListen : null,
        backTo: '/agent',
        body: signs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(message: e.toString()),
          data: (list) {
            if (list.isEmpty) return const InfoBanner(text: S.noDangerSignsCached);
            if (signId == null) return _SignList(signs: list);
            if (sign == null) return const InfoBanner(text: S.empty);
            return _DecisionSheet(sign: sign);
          },
        ),
      ),
    );
  }
}

class _SignList extends StatelessWidget {
  const _SignList({required this.signs});

  final List<DangerSign> signs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (signs.any((s) => s.provisional)) ...[const ProvisionalNote(), const SizedBox(height: AppSpacing.sm)],
        for (final sign in signs)
          Card(
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 32),
              title: Text(sign.label),
              subtitle: sign.hasDecisionAid ? null : const Text(S.decisionAidNotWritten),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(decisionAidPath(sign.id)),
            ),
          ),
      ],
    );
  }
}

class _DecisionSheet extends ConsumerWidget {
  const _DecisionSheet({required this.sign});

  final DangerSign sign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final services = ref.watch(agentHelpServicesProvider).valueOrNull ?? const <HelpService>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 40),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(sign.label, style: theme.textTheme.titleLarge)),
            ListenButton(text: decisionAidSpoken(sign), compact: true, mode: ListenMode.content, contentLang: 'fr'),
          ],
        ),
        if (sign.provisional) ...[const SizedBox(height: AppSpacing.sm), ProvisionalNote(source: sign.source)],
        if (sign.advice.isNotEmpty) ...[
          const SectionTitle(S.adviceLabel, listen: false),
          Text(sign.advice, style: theme.textTheme.bodyLarge),
        ],
        if (!sign.hasDecisionAid) ...[
          const SizedBox(height: AppSpacing.md),
          const InfoBanner(text: S.decisionAidNotWritten, icon: Icons.edit_note_rounded),
        ] else ...[
          if (sign.agentQuestions.isNotEmpty) ...[
            const SectionTitle(S.questionsToAsk, listen: false),
            for (final question in sign.agentQuestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text('• $question', style: theme.textTheme.bodyLarge),
              ),
          ],
          if (sign.referWhen != null) ...[
            const SectionTitle(S.whenToRefer, listen: false),
            InfoBanner(text: sign.referWhen!, icon: Icons.local_hospital_rounded, color: AppTheme.danger),
          ],
        ],
        const SectionTitle(S.servicesToCall, listen: false),
        if (services.isEmpty) const InfoBanner(text: S.noNumberCached),
        for (final service in services)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(service.name, style: theme.textTheme.titleMedium),
                  Text(
                    [
                      helpCategoryLabels[service.category] ?? service.category,
                      ?service.city,
                      if (!service.verified) S.notConfirmed,
                      if (service.verified) S.verifiedOn(frDate(service.verifiedAt)),
                    ].join(' · '),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.leaf, foregroundColor: Colors.white),
                    onPressed: () => callNumber(service.phone),
                    icon: const Icon(Icons.call_rounded, size: 28),
                    label: Text('${S.call} ${service.phone}'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
