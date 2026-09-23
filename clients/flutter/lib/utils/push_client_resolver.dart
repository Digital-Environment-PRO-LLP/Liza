import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

/// Что сообщить нативному слою iOS/macOS про чат, открытый сейчас на экране.
/// `AppDelegate.willPresent` по этому глушит уведомление о сообщении, которое и
/// так видно (жалоба 2026-09-15 «пришёл пуш о сообщении в активном чате»).
/// `null` — гасить нечего: чат не открыт или приложение не на переднем плане.
/// Незабытый сброс хуже лишнего баннера: проглоченное уведомление закрытого чата
/// пользователь не увидит вовсе. Семантика аккаунта — как у [pushInActiveRoomFor].
Map<String, Object?>? nativeActiveRoomPayload({
  required String? activeRoomId,
  required String? clientName,
  required bool foreground,
  required int clientCount,
}) {
  if (!foreground || activeRoomId == null) return null;
  return {
    'roomId': activeRoomId,
    'clientName': clientName,
    'singleClient': clientCount <= 1,
  };
}

const MethodChannel _apnsChannel = MethodChannel('com.prodamus.laba.liza/apns');

Future<void> sendNativeActiveRoom(Map<String, Object?>? payload) async {
  try {
    await _apnsChannel.invokeMethod('setActiveRoom', payload);
  } on PlatformException {
    // best-effort: без записи уведомление просто покажется, как раньше
  } on MissingPluginException {
    // платформа без нативного APNs-плагина
  }
}

/// Маршрутизация входящего пуша/тапа к аккаунту-получателю при мультиаккаунте.
///
/// На одном устройстве может быть несколько залогиненных клиентов (Лаба + своя
/// компания = два хоумсервера; у тестировщиков — три). Pusher регистрируется для
/// КАЖДОГО (`BackgroundPush.setupPush`), а получатель конкретного пуша определяется
/// ключом `client_name`, который клиент кладёт в `pusher.data.default_payload`
/// (Sygnal мержит его в top-level FCM data / APNs userInfo) и который же лежит в
/// `LizaPushPayload` локального уведомления. Резолв ОБЯЗАН случиться ДО
/// `getEventByPushNotification`: на чужом клиенте тот падает в generic-баннер.
///
/// Fallback без ключа (старые pushers до перерегистрации, нативный тап без
/// `client_name`): единственный клиент, у которого комната уже загружена
/// (`getRoomById`, без `waitForRoomInSync` — в фоновом isolate N×30с недопустимо),
/// иначе первый клиент + лог. Чистая функция ради стража
/// `RL-push-multiaccount-routing`.
Client clientForPush({
  required List<Client> clients,
  String? clientName,
  String? roomId,
  String? senderId,
}) {
  assert(clients.isNotEmpty, 'clientForPush: пустой список клиентов');
  if (clientName != null && clientName.isNotEmpty) {
    final byName = clients.firstWhereOrNull((c) => c.clientName == clientName);
    if (byName != null) return byName;
    Logs().w('[Push] client_name=$clientName не среди залогиненных — fallback');
  }
  if (roomId != null && roomId.isNotEmpty) {
    // Свой аккаунт-отправитель пуш о собственном сообщении не получает — при
    // общей комнате двух своих аккаунтов адресат заведомо не sender.
    final withRoom = clients
        .where(
          (c) =>
              c.getRoomById(roomId) != null &&
              (senderId == null || c.userID != senderId),
        )
        .toList(growable: false);
    if (withRoom.length == 1) return withRoom.single;
    if (withRoom.length > 1) {
      // Два своих аккаунта в одной комнате (личный чат между ними, сторис-комната
      // с двумя зрителями) — без ключа адресат неразличим; берём первого
      // детерминированно и говорим об этом в лог.
      Logs().w(
        '[Push] room $roomId есть у ${withRoom.length} клиентов, '
        'client_name отсутствует — выбран первый',
      );
      return withRoom.first;
    }
  }
  return clients.first;
}

/// Идентификатор системного уведомления комнаты — со скоупом аккаунта: два
/// аккаунта одного человека в одной комнате дают ДВА уведомления, а не
/// перезапись одного другим (`roomId.hashCode` без клиента их схлопывал).
int pushNotificationId(String? clientName, String? roomId) =>
    '${clientName ?? ''}_${roomId ?? ''}'.hashCode;

/// Нужно ли регистрировать pusher с `append: true`: только когда на ОДНОМ
/// хоумсервере залогинено ≥2 своих аккаунтов с одним push-токеном. Иначе
/// Synapse при `append:false` удаляет pushers ДРУГИХ пользователей с тем же
/// app_id+pushkey на этом HS (`remove_pushers_by_app_id_and_pushkey_not_user`) —
/// ровно так аккаунты №2/№3 сносили друг друга («были, пропали»). Для
/// единственного аккаунта на HS оставляем `false`: это страховка от stale pusher
/// чужого пользователя, залогинившегося на этом же телефоне офлайн-логаутом.
/// Детерминировано зависит только от состава клиентов, не от порядка вызовов.
bool pusherAppendFor(Client client, List<Client> clients) {
  final host = client.homeserver?.host;
  if (host == null) return false;
  final own = clients.where(
    (c) => c.isLogged() && c.homeserver?.host == host,
  );
  return own.length > 1;
}

/// Пуш пришёл в комнату, которую пользователь смотрит прямо сейчас (haptic
/// вместо баннера, как в Liza). «Активная» комната принадлежит АКТИВНОМУ
/// клиенту: тот же `roomId` у другого своего аккаунта (личный чат между своими
/// аккаунтами, сторис-комната с двумя зрителями) баннер не глушит.
/// [activeClientName] == null — одноклиентный вызов (совместимость).
bool pushInActiveRoomFor({
  required String? roomId,
  required String? activeRoomId,
  required String? activeClientName,
  required String clientName,
  required bool resumed,
}) =>
    roomId != null &&
    activeRoomId == roomId &&
    (activeClientName == null || activeClientName == clientName) &&
    resumed;
