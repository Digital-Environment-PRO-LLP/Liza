/// Нужно ли ChatList обрабатывать входящий URI из `AppLinks`.
///
/// На вебе `AppLinks.getInitialLink()` — это `window.location.href` самой
/// страницы (`web.liza.ru/i/<code>`), а не короткая ссылка `me.liza.ru`: его
/// уже разобрал роутер через `webInitialLocation` при старте. Без пропуска
/// host-гейтнутые парсеры дают null, и fallback `go('/rooms')` сбивал бы
/// пользователя с `/opening/<code>` обратно в список чатов. Runtime-стрим на
/// вебе не приходит, нативные initial/runtime-ссылки обрабатываются как прежде.
///
/// Чистая функция с явным `isWeb`: `kIsWeb` — константа компиляции, на
/// Dart-VM её не переключить.
bool shouldHandleIncomingUri({
  required bool isWeb,
  required bool isInitialLink,
}) =>
    !(isWeb && isInitialLink);
