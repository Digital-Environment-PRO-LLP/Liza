import 'package:flutter/material.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/l10n/l10n.dart';
import '../../../config/app_config.dart';

/// Плашка «Переслано [от X]» над пересланным сообщением (LABA-1991).
///
/// [name] — снимок имени оригинального автора на момент пересылки (кладётся в
/// `content['com.liza.forwarded'].from_name` при forward). null/пусто → показываем
/// просто «Переслано»: имя было недоступно (пустой displayname или автор не в
/// комнате-источнике) — честнее, чем зашитый localpart вида «User Xf12».
///
/// Данные приходят готовой строкой — виджет не поднимает Matrix Client и не ходит
/// в сеть, поэтому покрывается widget/golden-тестом без `prepareTestClient` (по
/// образцу [ReplyContent]).
class ForwardedContent extends StatelessWidget {
  final String? name;
  final bool ownMessage;

  const ForwardedContent({this.name, this.ownMessage = false, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final fontSize =
        AppConfig.messageFontSize * AppSettings.fontSizeFactor.value;
    final color = theme.brightness == Brightness.dark
        ? theme.colorScheme.onTertiaryContainer
        : ownMessage
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.tertiary;
    final trimmed = name?.trim();
    final label = (trimmed != null && trimmed.isNotEmpty)
        ? l10n.forwardedFrom(trimmed)
        : l10n.forwarded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.forward_outlined, size: fontSize + 2, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
              color: color,
              fontSize: fontSize,
            ),
          ),
        ),
      ],
    );
  }
}
