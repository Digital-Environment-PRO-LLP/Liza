import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/utils/miniapp_room.dart';
import 'package:liza/utils/miniapp_start_path.dart';

/// Реестр «какой бот несёт закреплённый mini App» для текущего пользователя.
///
/// Паритет с Liza: у бота с прикреплённым mini App в списке чатов есть
/// кнопка «Открыть», а внутри чата с ботом — кнопка «Открыть» слева от «+».
/// Связь бот↔приложение живёт в БД liza-bot-api (`miniapp_rooms.bot_mxid`), а не в
/// state-event DM-комнаты (бот в DM имеет PL 0 и не может писать state). Поэтому
/// источник истины — `GET {base}/liza/mybots` (владелец видит свои боты и app),
/// откуда строим карту `botMxid → MiniAppLaunch`. Скоуп — только СВОИ приложения
/// владельца (как и весь mini-app-функционал).
class BotMiniAppRegistry {
  BotMiniAppRegistry._();

  static final BotMiniAppRegistry instance = BotMiniAppRegistry._();

  /// Ревизия карты: бампается при успешном обновлении, чтобы виджеты
  /// (`ValueListenableBuilder`) перерисовались, когда данные приехали по сети
  /// (сам `/liza/mybots` не эмитит Matrix-события).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // botMxid → MiniAppLaunch, раздельно по homeserver host (в одном приложении
  // бывают и локальный, и prod-аккаунт — эндпоинты у них разные).
  final Map<String, Map<String, MiniAppLaunch>> _byHost = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Set<String> _inFlight = {};

  static const Duration _ttl = Duration(seconds: 45);

  /// Конфиг запуска mini App для бота (или `null`, если у бота нет приложения
  /// либо карта ещё не загружена).
  MiniAppLaunch? launchForBotMxid(Client client, String? botMxid) {
    if (botMxid == null) return null;
    final host = client.homeserver?.host ?? '';
    return _byHost[host]?[botMxid];
  }

  /// То же по комнате: mini App партнёра DM (бота). Для групп/не-DM — `null`.
  MiniAppLaunch? launchForRoom(Room room) =>
      launchForBotMxid(room.client, room.directChatMatrixID);

  /// Лениво подгружает карту для клиента (один запрос на homeserver, дедуп +
  /// TTL). Безопасно звать из `build` — повторные вызовы схлопываются.
  void ensureLoaded(Client client, {bool force = false}) {
    final host = client.homeserver?.host;
    final token = client.accessToken;
    if (host == null || host.isEmpty || token == null) return;
    if (_inFlight.contains(host)) return;
    final last = _fetchedAt[host];
    if (!force && last != null && DateTime.now().difference(last) < _ttl) {
      return;
    }
    _inFlight.add(host);
    _fetch(client, host, token).whenComplete(() => _inFlight.remove(host));
  }

  /// Форс-обновление после действия, меняющего привязку app↔бот (кнопка
  /// «Привязать к боту»): эндпоинт не пушит Matrix-события, поэтому дёргаем
  /// сами. Задержка — на обработку сервером (запись в БД происходит после того,
  /// как клиент отправил callback). Двухфазно: первый рефетч может успеть до
  /// записи сервера — второй гарантированно её застаёт. Так пилюля «Открыть» и
  /// кнопка «Открыть» в композере появляются сразу после привязки, а не по TTL.
  void scheduleRefresh(Client client) {
    Future.delayed(const Duration(milliseconds: 1500),
        () => ensureLoaded(client, force: true));
    Future.delayed(const Duration(milliseconds: 4000),
        () => ensureLoaded(client, force: true));
  }

  /// Beacon аналитики активности: пользователь открыл mini App (LABA-2364
  /// Блок D, D-γ). Fire-and-forget POST в liza-bot-api — ошибки/оффлайн глотаем,
  /// на открытие приложения это не влияет. Личность берёт сервер из
  /// Matrix-токена (не из тела), поэтому шлём только app_id.
  void recordOpen(Client client, String appId) {
    final host = client.homeserver?.host;
    final token = client.accessToken;
    if (host == null || host.isEmpty || token == null || appId.isEmpty) return;
    final base = AppConfig.lizaBotApiBaseForHomeserver(host);
    final hs = client.homeserver?.toString();
    Future(() async {
      try {
        await http.post(
          Uri.parse('$base/liza/miniapp-open'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            if (hs != null) 'X-Liza-Homeserver': hs,
          },
          body: jsonEncode({'app_id': appId}),
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        Logs().v('[BotMiniAppRegistry] open beacon failed: $e');
      }
    });
  }

  Future<void> _fetch(Client client, String host, String token) async {
    final base = AppConfig.lizaBotApiBaseForHomeserver(host);
    final url = '$base/liza/mybots';
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          if (client.homeserver != null)
            'X-Liza-Homeserver': client.homeserver!.toString(),
        },
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        Logs().w('[BotMiniAppRegistry] $url → ${resp.statusCode}');
        // Помечаем время попытки, чтобы не долбить эндпоинт каждым build при
        // ошибке (например, у аккаунта без liza-bot-api). Retry — по TTL.
        _fetchedAt[host] = DateTime.now();
        return;
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      _byHost[host] = parseBotMiniApps(data);
      _fetchedAt[host] = DateTime.now();
      revision.value++;
    } catch (e) {
      Logs().w('[BotMiniAppRegistry] load failed ($url): $e');
      _fetchedAt[host] = DateTime.now();
    }
  }
}

/// Чистый разбор ответа `/liza/mybots` в карту `botMxid → MiniAppLaunch`.
///
/// Берём только приложения с непустым `bot_mxid` и валидным `app_url` (клиент
/// открывает mini App только по https-ссылке). Если у бота несколько
/// приложений — берём первое: сервер отдаёт `created_at DESC`, т.е. самое
/// свежее «меню» бота. Вынесено из сервиса для юнит-теста без сети.
/// Название кнопки из BotFather: непустая строка после trim, иначе `null`
/// (клиент подставит дефолтное «Открыть»).
String? _cleanLabel(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, MiniAppLaunch> parseBotMiniApps(Map<String, dynamic> data) {
  final result = <String, MiniAppLaunch>{};
  final apps = data['apps'];
  if (apps is! List) return result;
  for (final raw in apps) {
    if (raw is! Map) continue;
    final a = raw.cast<String, Object?>();
    final botMxid = a['bot_mxid'];
    final url = a['app_url'];
    if (botMxid is! String || botMxid.isEmpty) continue;
    if (url is! String || url.isEmpty) continue;
    if (result.containsKey(botMxid)) continue; // первое = самое свежее
    // app_start_path — недоверенные данные: та же граница безопасности, что и
    // при чтении state-event (см. miniAppLaunchFromConfig). Невалидное → главная.
    final rawStart = a['app_start_path'];
    final startPath =
        (rawStart is String && isSafeStartPath(rawStart)) ? rawStart : '';
    final name = a['name'];
    final type = a['app_type'];
    result[botMxid] = MiniAppLaunch(
      appUrl: url,
      appId: (a['app_id'] as String?) ?? 'unknown',
      appName: (name is String && name.trim().isNotEmpty) ? name : 'Mini App',
      appType: (type is String && type.trim().isNotEmpty) ? type : 'third_party',
      appStartPath: startPath,
      // Настройки кнопок из BotFather. Отсутствует/не bool → включено (кнопки
      // видимы по умолчанию). Пустой/пробельный label → дефолт («Открыть»).
      composerButtonEnabled: a['composer_button_enabled'] != false,
      composerButtonLabel: _cleanLabel(a['composer_button_label']),
      listButtonEnabled: a['list_button_enabled'] != false,
      listButtonLabel: _cleanLabel(a['list_button_label']),
    );
  }
  return result;
}
