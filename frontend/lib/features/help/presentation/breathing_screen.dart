import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/laafi_scaffold.dart';

/// Respiration guidée : un cercle grandit (inspirer, 4 s) puis diminue
/// (souffler, 6 s), pendant la durée choisie. Rien d'autre à lire.
class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> with SingleTickerProviderStateMixin {
  static const _inhale = Duration(seconds: 4);
  static const _exhale = Duration(seconds: 6);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _inhale,
    reverseDuration: _exhale,
  );
  Timer? _timer;
  int _secondsLeft = 0;
  bool get _running => _timer != null;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (!_running) return;
      if (status == AnimationStatus.completed) _controller.reverse();
      if (status == AnimationStatus.dismissed) _controller.forward();
    });
  }

  void _start(int minutes) {
    _timer?.cancel();
    setState(() => _secondsLeft = minutes * 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) _stop();
    });
    _controller.forward(from: 0);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _controller.stop();
    _controller.animateTo(0, duration: const Duration(milliseconds: 600));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LaafiScaffold(
      title: S.breathing,
      listenText: S.breathingListen,
      protectedArea: true,
      backTo: '/help',
      body: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 300,
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final size = 120 + 160 * Curves.easeInOut.transform(_controller.value);
                  final inhaling = _controller.status == AnimationStatus.forward;
                  return Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [AppTheme.leaf.withValues(alpha: 0.85), AppTheme.sky.withValues(alpha: 0.6)],
                      ),
                    ),
                    child: Text(
                      _running ? (inhaling ? S.breatheIn : S.breatheOut) : '',
                      style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_running) ...[
            Text(
              '${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(onPressed: _stop, icon: const Icon(Icons.stop_rounded), label: const Text(S.stop)),
          ] else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final minutes in const [1, 3, 5])
                  FilledButton(onPressed: () => _start(minutes), child: Text('$minutes min')),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          TextButton.icon(
            onPressed: () => context.push('/help/directory?filter=listening'),
            icon: const Icon(Icons.hearing_rounded),
            label: const Text(S.listeningServices),
          ),
        ],
      ),
    );
  }
}
