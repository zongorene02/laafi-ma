import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../../carnet/domain/share_payload.dart';
import 'agent_gate.dart';

/// Lecture du QR code montré par une femme. Caméra sur Android ; sur le web,
/// on colle le contenu du code. Un code expiré est refusé.
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final _paste = TextEditingController();
  SharePayload? _payload;
  String? _error;
  bool _handled = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _read(String raw) {
    try {
      final payload = SharePayload.decode(raw);
      setState(() {
        _payload = payload;
        _error = null;
      });
    } on SharePayloadException catch (e) {
      setState(() {
        _payload = null;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final useCamera = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return AgentGate(
      child: LaafiScaffold(
        title: S.scanQr,
        backTo: '/agent',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_payload == null && useCamera)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: SizedBox(
                  height: 320,
                  child: MobileScanner(
                    onDetect: (capture) {
                      final raw = capture.barcodes.firstOrNull?.rawValue;
                      if (raw == null || _handled) return;
                      _handled = true;
                      _read(raw);
                    },
                  ),
                ),
              ),
            if (_payload == null && !useCamera) ...[
              TextField(
                controller: _paste,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: S.pasteQr),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(onPressed: () => _read(_paste.text), child: const Text('Afficher')),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              InfoBanner(text: _error!, color: AppTheme.danger, icon: Icons.error_outline_rounded),
            ],
            if (_payload != null) ...[
              SharedSummaryView(payload: _payload!),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _payload = null;
                  _handled = false;
                  _paste.clear();
                }),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Lire un autre code'),
              ),
            ],
            if (_error != null && useCamera)
              TextButton(
                onPressed: () => setState(() {
                  _error = null;
                  _handled = false;
                }),
                child: const Text(S.retry),
              ),
          ],
        ),
      ),
    );
  }
}

/// Affichage lisible du résumé partagé (clés compactes de `buildShareData`).
class SharedSummaryView extends StatelessWidget {
  const SharedSummaryView({super.key, required this.payload});

  final SharePayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = payload.data;
    Widget section(String title, List<String> lines) => Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            for (final line in lines) Text(line, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
    String line(String label, Object? value) => value == null ? '' : '$label : $value';
    List<String> clean(List<String> lines) => lines.where((l) => l.isNotEmpty).toList();

    final p = (d['p'] as Map?)?.cast<String, dynamic>();
    final g = (d['g'] as Map?)?.cast<String, dynamic>();
    final k = (d['k'] as Map?)?.cast<String, dynamic>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          text:
              'Code créé à ${hhmm(payload.generatedAt.toLocal())}, valable jusqu\'à ${hhmm(payload.expiresAt.toLocal())}.',
          icon: Icons.timer_rounded,
          color: AppTheme.leaf,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (p != null)
          section(
            'Profil santé',
            clean([
              line('Âge', p['age']),
              line('Groupe sanguin', p['bg']),
              line('Allergies', p['al']),
              line('Maladies', p['cc']),
              line('Traitements', p['ct']),
            ]),
          ),
        if (g != null)
          section(
            'Grossesse (estimations)',
            clean([
              line('DDR', frDate(g['lmp'])),
              line('Semaines', g['wk']),
              line('DPA', g['edd'] == null ? null : frDate(g['edd'])),
              line('Visites prénatales faites', g['pv']),
            ]),
          ),
        if (k != null)
          section(
            'Contraception',
            clean([line('Méthode', k['m']), line('Depuis', frDate(k['s'])), line('Renouvellement', frDate(k['n']))]),
          ),
        for (final c in (d['c'] as List? ?? const []).cast<Map>())
          section(
            'Consultation du ${frDate(c['d'])}',
            clean([
              line('Lieu', c['f']),
              line('Motif', c['r']),
              line('Conclusions', c['co']),
              line('Recommandations', c['re']),
            ]),
          ),
        if ((d['m'] as List? ?? const []).isNotEmpty)
          section('Médicaments', [
            for (final m in (d['m'] as List).cast<Map>())
              '${m['n']}${m['ds'] == null ? '' : ' — ${m['ds']}'}${m['t'] == null ? '' : ' (${(m['t'] as List).join(', ')})'}',
          ]),
        for (final e in (d['e'] as List? ?? const []).cast<Map>())
          section('Enfant : ${e['n']}', [
            if (e['b'] != null) 'Naissance : ${frDate(e['b'])}',
            for (final v in (e['v'] as List? ?? const []).cast<Map>()) 'Vaccin ${v['n']} : ${frDate(v['d'])}',
          ]),
      ],
    );
  }
}
