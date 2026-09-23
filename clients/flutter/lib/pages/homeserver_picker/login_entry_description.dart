import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';

/// Описание под логотипом на первом экране.
///
/// Объяснение «нет доступа» переехало на экран результата авторизации
/// (`AuthOutcomeView`) — до прохождения OIDC мы не знаем, есть ли у человека
/// аккаунт.
///
/// В dev-контуре, где первый экран совмещён с вводом телефона, описание
/// подаётся двумя блоками: слоган крупнее, пояснение мельче. В прод-ветке
/// (OIDC-кнопки) остаётся прежний единый абзац — экран там не менялся.
class LoginEntryDescription extends StatelessWidget {
  const LoginEntryDescription({super.key, this.compact = false});

  /// Двухблочная подача для экрана с вводом телефона.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    if (!compact) {
      return Text(
        l10n.lizaDescription,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // maxLines: 1 + downscale: слоган задуман одной строкой, но на узких
        // экранах он не влезает — вместо переноса ужимаем кегль.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            l10n.lizaTagline,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.lizaTaglineDetails,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
