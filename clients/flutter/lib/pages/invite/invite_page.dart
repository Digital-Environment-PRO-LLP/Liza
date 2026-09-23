import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:liza/l10n/l10n.dart';

/// Экран, показывающий результат обработки инвайт-ссылки (ошибки/состояния).
/// Используется для путей /invite/:code/:state.
class InvitePage extends StatelessWidget {
  final String code;
  final String state;

  const InvitePage({super.key, required this.code, required this.state});

  String _title(BuildContext context) {
    final l = L10n.of(context);
    switch (state) {
      case 'not-found':
        return l.invitationNotFound;
      case 'expired':
        return l.invitationExpired;
      case 'room-gone':
        return l.invitationRoomNoLongerExists;
      case 'needs-account':
        return l.invitationNeedsAccountOnTargetServer;
      case 'error':
      default:
        return l.invitationError;
    }
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).invitation)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _title(context),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: Text(L10n.of(context).goToHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
