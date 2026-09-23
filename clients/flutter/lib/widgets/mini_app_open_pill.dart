import 'package:flutter/material.dart';

/// Пилюля «Открыть» на строке чата с ботом, у которого закреплён mini App
/// (Liza-паритет). ЧИСТЫЙ виджет: реактивность (BotMiniAppRegistry +
/// ValueListenableBuilder) и текст (`L10n`) держит вызывающий
/// (`chat_list_item.dart`), сюда приходит готовая `label` и `onTap`. Так виджет
/// golden-тестируется без Matrix Client и без localizations (страж
/// ledger:RL-bot-miniapp-registry).
class MiniAppOpenPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const MiniAppOpenPill({required this.label, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
