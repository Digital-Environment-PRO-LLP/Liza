import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/web_url_normalizer.dart';

/// Экран ожидания, пока разрешается цель короткой ссылки.
///
/// Зачем: цепочка redeem → авто-инвайт → авто-join → появление комнаты в sync
/// занимает секунды. Без этого экрана пользователь после логина попадал в
/// список чатов (а иногда в пустой ChatPage на ещё не приехавшей комнате) и
/// решал, что ссылка не сработала.
class OpeningPage extends StatefulWidget {
  const OpeningPage({
    super.key,
    required this.code,
    required this.resolve,
    this.onNavigated = normalizeWebUrlAfterDeepLink,
  });

  /// Код ссылки — для диагностики и как ключ повторной попытки.
  final String code;

  /// Возвращает путь роутера, на который нужно уйти.
  final Future<String> Function() resolve;

  /// Вызывается ОДИН раз после успешной навигации на путь цели — на вебе
  /// чистит адресную строку от path-формы ссылки (`/i/<code>` → `/`), чтобы
  /// код не утекал в копии URL и не ломал перезагрузку. При ошибке резолва не
  /// вызывается: URL ещё нужен кнопке «Повторить». Параметр — ради теста.
  final void Function(String route) onNavigated;

  @override
  State<OpeningPage> createState() => _OpeningPageState();
}

class _OpeningPageState extends State<OpeningPage> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _failed = false);
    try {
      final path = await widget.resolve();
      if (!mounted) return;
      context.go(path);
      widget.onNavigated(path);
    } catch (e) {
      // resolveInviteTarget сам не бросает — сюда долетают только неожиданные
      // исключения (сбой роутера, программная ошибка), их нельзя терять молча.
      Logs().e('[DeepLink] OpeningPage.resolve failed (code=${widget.code}): $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _failed
                ? [
                    Icon(
                      Icons.link_off,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      L10n.of(context).openingLinkFailed,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _run,
                      child: Text(L10n.of(context).tryAgain),
                    ),
                  ]
                : [
                    const CircularProgressIndicator.adaptive(),
                    const SizedBox(height: 16),
                    Text(
                      L10n.of(context).openingLink,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
