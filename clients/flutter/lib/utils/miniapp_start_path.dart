/// Deep-link на конкретную страницу mini App (`app_start_path`).
///
/// Tilda и подобные SPA роутят товар ЧЕРЕЗ #-фрагмент
/// (`#!/tproduct/2413257851-1500470245901`). Чтобы инвайт открывал у redeemer'а
/// именно эту страницу, из текущего URL открытой страницы нужно вычленить
/// пользовательский маршрут, СРЕЗАВ всё, что инъектирует Liza (initData в
/// фрагменте, return-маркеры оплаты), и потом корректно собрать финальный URL,
/// НЕ затирая маршрут приложения.
///
/// Эти функции — единственный источник истины для формата `app_start_path` на
/// клиенте; их зеркало на сервере — `_sanitize_start_path` в auth-proxy
/// (`app/invites/api.py`). Чистые (без webview) — закрепляются unit-стражем
/// RL-miniapp-start-path.
library;

/// Маркеры, по которым фрагмент опознаётся как Liza-инъекция (подписанная
/// initData + транспортные/return поля). Если фрагмент их содержит — это наш
/// служебный фрагмент (страница на «главной» приложения), маршрута в нём нет.
const _lizaFragmentMarkers = <String>[
  'lizaWebAppData',
  'theme_params=',
  'platform=',
  'payment_result=',
  'liza_invoice_id=',
];

/// Query-параметры, которые кладёт сам клиент (возврат с оплаты) — не часть
/// пользовательского маршрута, срезаем при захвате.
const _lizaQueryKeys = <String>['payment_result', 'liza_invoice_id'];

/// Извлекает deep-link-хвост (`app_start_path`) текущей страницы относительно
/// [appUrl]. Возвращает `''`, если хвоста нет (главная) или страница на чужом
/// origin (платёжный шлюз, 3DS) — оттуда маршрут брать нельзя.
///
/// Берём ТОЛЬКО фрагмент и query (без path): итоговый открытый URL обязан
/// остаться на том же origin, а смена path — лишняя поверхность (раздел
/// `/admin`, path-traversal на стороне приложения). Для Tilda товар во
/// фрагменте, path не меняется — кейс покрыт полностью.
String extractStartPath({required String appUrl, required String currentUrl}) {
  final cur = Uri.tryParse(currentUrl);
  final app = Uri.tryParse(appUrl);
  if (cur == null || app == null) return '';
  // Чужой host/схема — мы ушли с приложения (оплата/3DS), хвост невалиден.
  if (cur.scheme != app.scheme || cur.host != app.host) return '';

  final cleanQuery = Map.of(cur.queryParameters)
    ..removeWhere((k, _) => _lizaQueryKeys.contains(k));
  final qs = cleanQuery.isEmpty
      ? ''
      : '?${cleanQuery.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';

  final frag = _stripLizaFragment(cur.fragment);
  final fr = frag.isEmpty ? '' : '#$frag';

  return '$qs$fr';
}

/// Бинарно: если фрагмент — Liza-инъекция (initData/return-маркеры), весь
/// фрагмент наш → маршрута нет (`''`). Иначе фрагмент целиком пользовательский
/// (маршрут SPA) → отдаём как есть. Per-token разбор тут опасен: initData
/// содержит неизвестный набор подключей (auth_date/hash/user/...), их перечень
/// дрейфует — поэтому опознаём по характерным маркерам и режем целиком.
String _stripLizaFragment(String fragment) {
  if (fragment.isEmpty) return '';
  for (final marker in _lizaFragmentMarkers) {
    if (fragment.contains(marker)) return '';
  }
  return fragment;
}

/// Собирает финальный URL для открытия mini App: [appUrl] + [startPath] и, при
/// необходимости, фрагмент initData — НЕ затирая маршрут приложения.
///
/// Конфликт: и маршрут SPA (`#!/...`), и initData претендуют на единственный
/// `#`-фрагмент. Если [startPath] сам начинается с фрагмента — initData в URL
/// НЕ кладём вовсе (сторонний сайт её игнорирует; для shell/first_party initData
/// доставляется отдельно). Если фрагмента в [startPath] нет — склеиваем initData
/// через `#`.
String composeMiniAppUrl({
  required String appUrl,
  String startPath = '',
  String? initDataFragment,
}) {
  final hasFragInStart = startPath.contains('#');
  var url = '$appUrl$startPath';
  if (initDataFragment != null && initDataFragment.isNotEmpty && !hasFragInStart) {
    final sep = url.contains('#') ? '&' : '#';
    url = '$url$sep$initDataFragment';
  }
  return url;
}

/// Валиден ли [startPath] как deep-link mini App. Граница безопасности на
/// клиенте (зеркало `_sanitize_start_path` в auth-proxy). Только фрагмент/query
/// (`#`/`?`), без смены origin/схемы/пути и инъекций.
bool isSafeStartPath(String startPath) {
  if (startPath.isEmpty || startPath.length > 512) return false;
  final c = startPath[0];
  if (c != '#' && c != '?') return false;
  if (startPath.contains('://') ||
      startPath.startsWith('//') ||
      startPath.startsWith('/\\')) {
    return false;
  }
  final low = startPath.toLowerCase();
  if (low.startsWith('javascript:') || low.startsWith('data:')) return false;
  for (final unit in startPath.codeUnits) {
    if (unit < 0x20 || unit == 0x7F) return false;
  }
  return true;
}
