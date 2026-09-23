import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';

/// Исход авторизации, когда аккаунта в Liza нет.
enum AuthOutcome {
  /// Аккаунта нет и инвайта не было — показываем путь «оставить заявку».
  accessNotGranted,

  /// Инвайт был, но ссылка недействительна (отозвана или не существует).
  /// Отдельный исход: человек пришёл по ссылке, и дело в ней, а не в правах.
  inviteInvalid,
}

/// Код ошибки от `/api/auth/status` -> исход. `null` — код нам неизвестен,
/// показывать экран исхода не нужно (обрабатывается как обычная ошибка).
AuthOutcome? authOutcomeFromErrorCode(String? code) {
  switch (code) {
    case 'access_not_granted':
      return AuthOutcome.accessNotGranted;
    case 'invite_invalid':
      return AuthOutcome.inviteInvalid;
    default:
      return null;
  }
}

/// Экран результата авторизации для случая «аккаунта в Liza нет».
///
/// Показывается ПОСЛЕ прохождения OIDC, а не до него: человек сначала
/// регистрируется в ProdamusID (конверсия), и только затем узнаёт, что
/// доступа в Liza у него пока нет. Аккаунт в Liza при этом не создаётся —
/// остаётся только аккаунт в OIDC.
class AuthOutcomeView extends StatelessWidget {
  const AuthOutcomeView({
    super.key,
    required this.outcome,
    required this.requestAccessUrl,
    required this.onRequestAccess,
    required this.onBack,
  });

  final AuthOutcome outcome;
  final String? requestAccessUrl;
  final VoidCallback onRequestAccess;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final base = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final url = requestAccessUrl;
    final showRequestAccess =
        outcome == AuthOutcome.accessNotGranted &&
        url != null &&
        url.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (outcome == AuthOutcome.inviteInvalid)
              Text(
                l10n.inviteLinkInvalid,
                textAlign: TextAlign.center,
                style: base,
              )
            else
              // Text.rich, а не RichText: смешанное начертание нужно, но
              // текст должен оставаться доступным поиску по тексту
              // (find.textContaining обходит Text, но не голый RichText).
              Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    TextSpan(text: '${l10n.noAccessTitle}\n\n'),
                    TextSpan(
                      text: '${l10n.noAccessSellerQuestion}\n',
                      style: base?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: l10n.noAccessSellerHint),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 32),
            if (showRequestAccess) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: onRequestAccess,
                child: Text(l10n.requestAccess),
              ),
              const SizedBox(height: 12),
            ],
            TextButton(onPressed: onBack, child: Text(l10n.back)),
          ],
        ),
      ),
    );
  }
}
