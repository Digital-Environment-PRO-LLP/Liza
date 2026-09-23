import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/direct_chat_ensure.dart';
import 'package:liza/pages/chat/mini_app_web_view.dart';
import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/miniapp_room.dart';
import 'package:liza/utils/miniapp_start_path.dart';
import 'package:liza/widgets/liza_app.dart';
import 'package:liza/widgets/matrix.dart';

/// Итог обработки mini-app-инвайта.
///
/// [opened] — mini App уже открыт в WebView поверх UI: вызывающему НЕ нужно
/// навигировать в чат. [dmRoomId] — fallback: куда перейти (DM с launch-карточкой),
/// если авто-открытие не удалось (бот не успел создать комнату-лаунчер).
class MiniAppInviteOutcome {
  final bool opened;
  final String? dmRoomId;
  const MiniAppInviteOutcome({required this.opened, this.dmRoomId});
}

/// Обрабатывает redeem mini-app-инвайта (`status == 'miniapp_invite'`).
///
/// Ссылка ведёт не в общую комнату владельца, а на ПРИЛОЖЕНИЕ. Цель — открыть
/// mini App СРАЗУ на нужной странице (`app_start_path` из ссылки), а не показать
/// launch-карточку, которую надо нажимать вручную.
///
/// Поток:
///  1. Если mini App уже подключён (есть комната-лаунчер с этим app) — открываем
///     сразу, без сигнала боту.
///  2. Иначе сигналим боту (`com.liza.miniapp.data` kind=miniapp_created) — он
///     идемпотентно по (app, пользователь) создаёт персональную комнату-лаунчер.
///  3. Ждём появления этой комнаты в sync (бот создаёт её асинхронно) с
///     таймаутом и открываем mini App.
///  4. Если за таймаут комната не появилась — fallback: возвращаем DM, чтобы
///     вызывающий перешёл в чат с launch-карточкой (открыть вручную).
Future<MiniAppInviteOutcome> handleMiniAppInviteRedeem(
  Client client,
  InviteRedeemResult result,
) async {
  // Окно мессенджера на передний план: deep-link liza:// из браузера на macOS
  // доставляет ссылку, но окно не активирует (остаётся позади браузера).
  _bringMacOsWindowToFront();

  final appUrl = result.appUrl;
  if (appUrl == null || appUrl.isEmpty) {
    Logs().w('[MiniAppInvite] redeem без app_url');
    return const MiniAppInviteOutcome(opened: false);
  }
  // app_id может отсутствовать у легаси-конфига — дефолт как в
  // miniAppLaunchFromConfig (а не отбрасываем валидную ссылку).
  final appId = (result.appId?.isNotEmpty ?? false) ? result.appId! : 'unknown';

  // Deep-link из ССЫЛКИ (приоритетнее app_start_path в конфиге комнаты: бот мог
  // записать главную, если сигнал был без пути). Валидируем как границу.
  final rawStartPath = result.appStartPath;
  final safeStartPath =
      (rawStartPath != null && isSafeStartPath(rawStartPath)) ? rawStartPath : null;

  // 1) Уже подключён? Открываем сразу, сигнал боту не нужен.
  final existing = _findLauncherRoom(client, appId, appUrl);
  if (existing != null) {
    if (_tryOpenMiniApp(existing, safeStartPath)) {
      return const MiniAppInviteOutcome(opened: true);
    }
    return MiniAppInviteOutcome(opened: false, dmRoomId: existing.id);
  }

  // Бот приложения живёт на HS приложения (serverName из redeem); для прод это
  // совпадает с дефолтным lizaMxid. Локально/на компаниях — `@liza:<hs>`.
  final serverName = result.serverName;
  final botMxid = (serverName != null && serverName.isNotEmpty)
      ? '@liza:$serverName'
      : MatrixState.lizaMxid;

  String? dmRoomId;
  try {
    // 2) Сигналим боту — он создаст персональную комнату-лаунчер.
    dmRoomId = await _findOrCreateLizaDm(client, botMxid);
    final room = client.getRoomById(dmRoomId);
    if (room == null) {
      Logs().w('[MiniAppInvite] DM $dmRoomId не в client.rooms после создания');
      return MiniAppInviteOutcome(opened: false, dmRoomId: dmRoomId);
    }
    await room.sendEvent({
      'msgtype': 'com.liza.miniapp.data',
      'body': 'Подключение приложения',
      'app_id': appId,
      'data': {
        'kind': 'miniapp_created',
        'app_id': appId,
        'app_url': appUrl,
        'app_name': result.appName ?? 'Mini App',
        'app_type': result.appType ?? 'third_party',
        if (safeStartPath != null) 'app_start_path': safeStartPath,
        // Серверный якорь владельца из redeem (link.room_id): бот резолвит по нему
        // мерчанта и включает релей «Входящие» (переписка клиента → владельцу).
        // Наличие поля = «это redeem по ссылке», а не connect-сигнал мерчанта.
        if (result.ownerRoomId != null && result.ownerRoomId!.isNotEmpty)
          'owner_room_id': result.ownerRoomId,
      },
    });
  } catch (e, s) {
    Logs().e('[MiniAppInvite] не удалось просигналить боту', e, s);
    return MiniAppInviteOutcome(opened: false, dmRoomId: dmRoomId);
  }

  // 3) Ждём комнату-лаунчер (бот создаёт её асинхронно, появляется со следующим
  //    sync; cross-HS federation добавляет задержку — таймаут 15с).
  final launcher = await _awaitLauncherRoom(client, appId, appUrl);
  if (launcher != null && _tryOpenMiniApp(launcher, safeStartPath)) {
    return const MiniAppInviteOutcome(opened: true);
  }

  // 4) Fallback — DM с launch-карточкой (пользователь откроет вручную).
  return MiniAppInviteOutcome(opened: false, dmRoomId: dmRoomId);
}

/// Находит комнату-лаунчер этого mini App (state-event com.liza.miniapp.config).
///
/// Матч по `app_id`; при легаси-`unknown` (пустой app_id) — фоллбэк по `app_url`,
/// иначе два приложения без app_id схватили бы комнату друг друга.
Room? _findLauncherRoom(Client client, String appId, String appUrl) {
  for (final room in client.rooms) {
    final launch = miniAppLaunchForRoom(room);
    if (launch == null) continue;
    if (appId != 'unknown' && launch.appId == appId) return room;
    if (appId == 'unknown' && launch.appUrl == appUrl) return room;
  }
  return null;
}

/// Ждёт появления комнаты-лаунчера через короткие oneShotSync (паттерн
/// _waitForRoomInSync из routes.dart). Без вечного зависания: deadline.
Future<Room?> _awaitLauncherRoom(
  Client client,
  String appId,
  String appUrl, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final existing = _findLauncherRoom(client, appId, appUrl);
  if (existing != null) return existing;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await client.oneShotSync();
    final room = _findLauncherRoom(client, appId, appUrl);
    if (room != null) return room;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  Logs().w('[MiniAppInvite] комната-лаунчер app=$appId не появилась за $timeout');
  return null;
}

/// Открывает mini App из комнаты-лаунчера. Контекст берём из глобального
/// navigatorKey — хелпер работает вне дерева виджетов; открытие планируем на
/// следующий кадр (дерево должно стоять после redirect/логина).
bool _tryOpenMiniApp(Room room, String? startPath) {
  final launch = miniAppLaunchForRoom(room);
  if (launch == null) return false;
  final ctx = LizaApp.router.routerDelegate.navigatorKey.currentContext;
  if (ctx == null) return false;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = LizaApp.router.routerDelegate.navigatorKey.currentContext;
    if (c == null || !c.mounted) return;
    MiniAppWebView.open(
      context: c,
      appUrl: launch.appUrl,
      appId: launch.appId,
      appName: launch.appName,
      room: room,
      appType: launch.appType,
      // startPath из ссылки приоритетнее, чем в конфиге комнаты.
      appStartPath: (startPath != null && startPath.isNotEmpty)
          ? startPath
          : launch.appStartPath,
    );
  });
  return true;
}

/// Находит существующий DM именно с этим bot-аккаунтом, иначе создаёт.
///
/// Сверяем ПОЛНЫЙ mxid, а не localpart: в cross-HS бандле у пользователя может
/// быть DM с `@liza` на ДРУГОМ HS, чем хостящий приложение (serverName из
/// redeem) — туда сигнал слать нельзя, тот бот про это приложение не знает.
Future<String> _findOrCreateLizaDm(Client client, String botMxid) async {
  for (final room in client.rooms) {
    if (room.directChatMatrixID == botMxid) return room.id;
  }
  return client.ensureDirectChat(botMxid);
}

const _macWindowChannel = MethodChannel('liza/macos_window');

/// На macOS выводит окно приложения на передний план (см. AppDelegate). No-op на
/// других платформах и при отсутствии обработчика канала.
void _bringMacOsWindowToFront() {
  if (defaultTargetPlatform != TargetPlatform.macOS) return;
  _macWindowChannel.invokeMethod<void>('bringToFront').catchError((_) {});
}
