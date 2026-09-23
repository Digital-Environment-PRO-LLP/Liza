import 'package:flutter/foundation.dart';

import 'package:universal_html/html.dart' as html;

/// Убирает path-форму короткой ссылки из адресной строки веб-клиента после
/// того, как цель разрешена.
///
/// Веб на hash-стратегии: при внутренней навигации движок переписывает только
/// `#…`, а `pathname` сохраняет (`HashUrlStrategy.prepareExternalUrl`). После
/// старта с `web.liza.ru/i/<code>` адресная строка навсегда (до перезагрузки)
/// оставалась бы `web.liza.ru/i/<code>#/rooms/…`: копия/закладка вкладки
/// уносила бы чужой invite-код, а перезагрузка игнорировала бы
/// `webInitialLocation` (initialLocation роутера применяется только при
/// пустом hash) — ссылка «протекала» бы в чужую комнату.
///
/// Вызывать ТОЛЬКО после успешного резолва в `OpeningPage`, никогда в
/// pre-login редиректах: там `Uri.base` ещё должен прочитать экран входа
/// (`_restoreInviteCodeForWeb`). Вне веба — no-op.
void normalizeWebUrlAfterDeepLink(String route) {
  if (!kIsWeb) return;
  final hash = route.isEmpty || route == '/' ? '' : '#$route';
  html.window.history.replaceState(null, '', '/$hash');
}
