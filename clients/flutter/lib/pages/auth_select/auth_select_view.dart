import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/auth_select/auth_select.dart';
import 'package:liza/widgets/layouts/login_scaffold.dart';
import 'package:liza/widgets/matrix.dart';

class AuthSelectView extends StatelessWidget {
  final AuthSelectController controller;

  const AuthSelectView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoginScaffold(
      enforceMobileMode: Matrix.of(
        context,
      ).widget.clients.any((client) => client.isLogged()),
      appBar: AppBar(
        leading:
            (controller.isLoading || controller.isSelecting)
                ? null
                : const Center(child: BackButton()),
        automaticallyImplyLeading:
            !(controller.isLoading || controller.isSelecting),
        title: null,
      ),
      body: _buildBody(context, theme),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    // Loading state
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    // Error state without data (initial load failed)
    if (controller.error != null && controller.selectData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                controller.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: controller.retry,
                child: Text(L10n.of(context).tryAgain),
              ),
            ],
          ),
        ),
      );
    }

    final data = controller.selectData!;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Hero(
                      tag: 'info-logo',
                      child: Image.asset(
                        './assets/banner_transparent.png',
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    data.accounts.isEmpty
                        ? L10n.of(context).accountNotFound
                        : L10n.of(context).selectAccount,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data.accounts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        L10n.of(context).multipleAccountsHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (controller.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32.0,
                        vertical: 8.0,
                      ),
                      child: Text(
                        controller.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Account list
                  ...data.accounts.map(
                    (account) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 4.0,
                      ),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                account.isDefault
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.person,
                              color:
                                  account.isDefault
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme
                                          .colorScheme
                                          .onSurfaceVariant,
                            ),
                          ),
                          title: Text(account.localpart),
                          subtitle: Text(account.serverName),
                          trailing:
                              controller.isSelecting
                                  ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator.adaptive(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                          enabled: !controller.isSelecting,
                          onTap:
                              () => controller.selectAccount(
                                account.serverName,
                              ),
                        ),
                      ),
                    ),
                  ),
                  // Show hint about contacting admin if no accounts
                  if (data.accounts.isEmpty) ...[
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        L10n.of(context).contactAdminForAccess,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
