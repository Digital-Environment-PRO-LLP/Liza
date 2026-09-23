import 'package:flutter/material.dart';

/// Кнопка «Открыть» слева от «+» в композере (menu button бота, Liza-паритет).
/// ЧИСТЫЙ виджет: гейты видимости, реактивность (реестр) и текст (`L10n`) держит
/// вызывающий (`chat_input_row.dart`), сюда — готовая `label` и `onTap`. Так
/// golden-тестируется без Matrix Client и без localizations
/// (страж ledger:RL-bot-miniapp-registry).
class MiniAppComposerButton extends StatelessWidget {
  final double height;
  final String label;
  final VoidCallback onTap;

  const MiniAppComposerButton({
    required this.height,
    required this.label,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(label),
      ),
    );
  }
}
