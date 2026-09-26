import 'dart:async';

import 'package:flutter/foundation.dart';

/// Выключает нативное контекстное меню браузера на Web, чтобы правый клик
/// показывал только наше меню (поповер сообщения, меню ссылки, меню чата).
/// Без этого Chrome открывал своё меню поверх нашего (заявка поддержки №41).
///
/// После выключения Web ведёт себя как нативная macOS-сборка: поля ввода и
/// `SelectionArea` показывают тулбары Flutter вместо меню браузера.
///
/// `isWeb` и `disable` параметризованы, потому что
/// `BrowserContextMenu.disableContextMenu` содержит `assert(kIsWeb)`, а `kIsWeb`
/// — константа компиляции: иначе поведение не проверить host-тестом.
void configureBrowserContextMenu({
  required bool isWeb,
  required Future<void> Function() disable,
}) {
  if (!isWeb) return;
  unawaited(
    disable().catchError(
      (Object e) => debugPrint('[BOOT] disableContextMenu failed: $e'),
    ),
  );
}
