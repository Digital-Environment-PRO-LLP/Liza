import 'package:matrix/matrix.dart';

/// ВРЕМЕННАЯ диагностика редкого прод-бага «свежий чат помечен прочитанным без
/// индикатора непрочитанного».
///
/// Инцидент 2026-07-29 (aleksandr.novokshonov): на холодном старте с оборванной
/// связью (в логе весь отрезок 13:02→13:16 — `Client has not connection to the
/// server`) список показывал свежие превью двух верхних чатов (12:57/12:58) БЕЗ
/// точки/счётчика. Чистый `/sync` не прошёл, поэтому серверный
/// `notificationCount` не доехал, а `hasNewMessages` не спас. Баг самоустранился
/// после нормальной синхронизации и НЕ воспроизводится (пользователь уже прочёл
/// те чаты; в норме счётчики/точки появляются). Чаты НЕ заглушены.
///
/// Поскольку по логу нельзя развести причины (он не пишет per-room квитанции и
/// состояние sync), пишем компактную запись при построении списка для комнаты,
/// которая ВЫГЛЯДИТ прочитанной, хотя моя квитанция стоит НЕ на последнем чужом
/// сообщении. При рецидиве лог покажет точную причину (сервисный счётчик,
/// позиция квитанции, синканы ли комната/клиент) — правка будет прицельной.
///
/// Снимается полностью: удалить этот файл и единственный вызов
/// `UnreadDiagnostics.maybeLog` в `chat_list_item.dart`.
class UnreadDiagnostics {
  /// Пары `roomId:lastEventId`, уже разобранные в этом процессе. Каждую
  /// оцениваем максимум раз, чтобы тяжёлый `receiptState` (полный JSON-парс
  /// квитанций) и запись в лог не срабатывали на КАЖДЫЙ ребилд списка.
  static final Set<String> _seen = {};

  /// Чистый предикат: комната «выглядит прочитанной», хотя последнее
  /// отображаемое сообщение — чужое и моя квитанция НЕ на нём. Вынесен ради
  /// теста без Room (как `read_marker_logic.dart`).
  static bool looksReadButUnreceipted({
    required bool isUnread,
    required bool hasNewMessages,
    required bool lastEventFromOther,
    required bool lastEventIsPreviewType,
    required String lastEventId,
    required String? ownReceiptEventId,
  }) {
    if (!lastEventFromOther || !lastEventIsPreviewType) return false;
    // Индикатор непрочитанного уже показан — всё в порядке.
    if (isUnread || hasNewMessages) return false;
    // Моя квитанция стоит на последнем сообщении → честно прочитано.
    return ownReceiptEventId != lastEventId;
  }

  /// Вызывать в `build` элемента списка. Дешёвые гейты и дедупликация идут
  /// ПЕРЕД тяжёлым `receiptState`, поэтому на обычную комнату это почти
  /// бесплатно.
  static void maybeLog(Room room) {
    final lastEvent = room.lastEvent;
    if (lastEvent == null) return;
    final myId = room.client.userID;
    if (myId == null) return;
    if (lastEvent.senderId == myId) return;
    if (!room.client.roomPreviewLastEvents.contains(lastEvent.type)) return;

    // Каждую (комната, последнее событие) оцениваем один раз за процесс.
    final key = '${room.id}:${lastEvent.eventId}';
    if (!_seen.add(key)) return;

    final own = room.receiptState.global.latestOwnReceipt;
    final suspicious = looksReadButUnreceipted(
      isUnread: room.isUnread,
      hasNewMessages: room.hasNewMessages,
      lastEventFromOther: true,
      lastEventIsPreviewType: true,
      lastEventId: lastEvent.eventId,
      ownReceiptEventId: own?.eventId,
    );
    if (!suspicious) return;

    final lastTs = lastEvent.originServerTs.millisecondsSinceEpoch;
    final ownReceiptOnLast =
        lastEvent.receipts.any((r) => r.user.senderId == myId);

    Logs().i(
      '[UnreadDiag] looks-read-but-behind '
      'room=${room.id} '
      'notif=${room.notificationCount} highlight=${room.highlightCount} '
      'markedUnread=${room.markedUnread} '
      'lastEvent=${lastEvent.eventId} sender=${lastEvent.senderId} '
      'lastTs=$lastTs type=${lastEvent.type} '
      'ownReceipt=${own?.eventId} ownTs=${own?.ts ?? 0} '
      'ownReceiptOnLast=$ownReceiptOnLast '
      'roomPrevBatchNull=${room.prev_batch == null} '
      'clientPrevBatchNull=${room.client.prevBatch == null}',
    );
  }
}
