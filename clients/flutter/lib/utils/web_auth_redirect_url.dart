/// URL страницы-приёмника OIDC-результата (`flutter_web_auth_2`) для веба.
///
/// `auth.html` лежит в КОРНЕ раздачи, поэтому путь всегда абсолютный.
/// Относительное разрешение от текущего URL (`resolveUri`) с вложенной
/// страницы давало `/i/auth.html`, `/rooms/auth.html` и т.п. — таких файлов
/// нет, nginx отдавал SPA-fallback (`index.html`, код 200), результат
/// авторизации не доезжал до вкладки, и пользователя возвращало на пустой
/// экран входа. Ломался ЛЮБОЙ вход не с корня, в том числе переход по
/// инвайту `/i/<code>` (инцидент 2026-08-04).
///
/// Query и fragment текущей страницы отбрасываем: приёмнику они не нужны, а
/// `#/home` от go_router ломал бы сверку redirect_uri на стороне провайдера
/// (он сравнивается посимвольно).
///
/// Собираем [Uri] явно, а не через `replace`: `query: null` там значит
/// «оставить как было» (query не удалится), а `query: ''` оставляет висячие
/// `?` и `#` — оба варианта дают строку, не равную зарегистрированному
/// redirect_uri.
String webAuthRedirectUrl(String currentHref) {
  final current = Uri.parse(currentHref);
  return Uri(
    scheme: current.scheme,
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: '/auth.html',
  ).toString();
}
