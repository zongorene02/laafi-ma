import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/laafi_scaffold.dart';
import '../data/agent_repository.dart';

/// L'espace agent exige une connexion de rôle `agent` (`POST /auth/login`).
class AgentGate extends ConsumerWidget {
  const AgentGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(agentSessionProvider);
    return session.when(
      loading: () => const LaafiScaffold(
        title: S.agentTitle,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const AgentLoginScreen(),
      data: (user) => user == null ? const AgentLoginScreen() : child,
    );
  }
}

class AgentLoginScreen extends ConsumerStatefulWidget {
  const AgentLoginScreen({super.key});

  @override
  ConsumerState<AgentLoginScreen> createState() => _AgentLoginScreenState();
}

class _AgentLoginScreenState extends ConsumerState<AgentLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(agentSessionProvider.notifier).login(_email.text.trim(), _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LaafiScaffold(
      title: S.agentLogin,
      listenText: S.tileAgentListen,
      body: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            const Icon(Icons.badge_rounded, size: 72),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: S.email, prefixIcon: Icon(Icons.alternate_email_rounded)),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: S.password, prefixIcon: Icon(Icons.key_rounded)),
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[
              InfoBanner(text: _error!, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: AppSpacing.md),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _login,
              icon: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.login_rounded),
              label: const Text(S.login),
            ),
          ],
        ),
      ),
    );
  }
}
