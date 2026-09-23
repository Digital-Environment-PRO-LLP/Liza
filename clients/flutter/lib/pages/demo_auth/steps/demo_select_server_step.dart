import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/widgets/demo_auth_scaffold.dart';

/// Выбор инстанса, когда аккаунты есть на нескольких серверах.
///
/// Вид повторяет штатный `AuthSelectView`: тот экран завязан на
/// `AuthProxyService` и `session_state` OIDC-флоу, поэтому переиспользован
/// не он сам, а его раскладка и строки локализации.
class DemoSelectServerStep extends StatelessWidget {
  const DemoSelectServerStep({super.key, required this.controller});

  final DemoAuthFlowController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return DemoAuthScaffold(
      title: l10n.selectAccount,
      subtitle: l10n.multipleAccountsHint,
      onBack: controller.back,
      error: controller.error,
      errorCode: controller.errorCode,
      ticket: controller.ticket,
      step: 'select_server',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final account in controller.accounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: account.isDefault
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.person,
                      color: account.isDefault
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(account.localpart),
                  subtitle: Text(account.serverName),
                  trailing: controller.isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.arrow_forward_ios, size: 16),
                  enabled: !controller.isLoading,
                  onTap: () => controller.selectServer(account.serverName),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
