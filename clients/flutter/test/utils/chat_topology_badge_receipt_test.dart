// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

import 'test_client.dart';

/// Receipt-based гейт `countsTowardAppBadge` (RL-badge-receipt-based).
///
/// Инвариант: застрявший серверный `notificationCount` (Synapse не обнулил
/// `event_push_summary.notif_count` — механизм NULL-receipt для федеративных
/// событий) НЕ должен раздувать бейдж, ЕСЛИ моя квитанция уже покрыла
/// последнее preview-событие. При этом реальные непрочитанные (в т.ч.
/// федеративные сообщения после receipt) и неоцениваемые комнаты (нет
/// lastEvent) — остаются в бейдже (fail-safe против недосчёта).
///
/// ledger:RL-badge-receipt-based
void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  Room newRoom() => Room(id: '!r:example.invalid', client: client)
    ..setState(
      Event(
        eventId: '\$create',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomCreate,
        content: {},
        room: Room(id: '!r:example.invalid', client: client),
        stateKey: '',
      ),
    );

  Event msg({
    required int ts,
    String sender = '@other:example.invalid',
    String type = EventTypes.Message,
  }) {
    final room = Room(id: '!r:example.invalid', client: client);
    return Event(
      eventId: '\$msg$ts',
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      type: type,
      content: {'msgtype': 'm.text', 'body': 'hi'},
      room: room,
    );
  }

  void setReceipt(Room room, {required String eventId, required int ts}) {
    room.roomAccountData[LatestReceiptState.eventType] = BasicEvent(
      type: LatestReceiptState.eventType,
      content: {
        'global': {
          'latest': {'e': eventId, 'ts': ts},
          'others': <String, dynamic>{},
        },
      },
    );
  }

  group('countsTowardAppBadge receipt-based gate', () {
    test('AC:RL-badge-receipt-based/1 notif>0 + квитанция покрыла lastEvent → '
        'НЕ в бейдж (застрявший вычищен)', () {
      final room = newRoom()
        ..notificationCount = 3
        ..lastEvent = msg(ts: 1000);
      setReceipt(room, eventId: '\$msg1000', ts: 2000); // ts >= lastEvent.ts
      expect(room.hasNewMessages, isFalse); // sanity: SDK видит прочитанным
      expect(room.countsTowardAppBadge, isFalse);
    });

    test('AC:RL-badge-receipt-based/2 notif>0 + квитанции нет → в бейдж '
        '(реальный непрочитанный)', () {
      final room = newRoom()
        ..notificationCount = 3
        ..lastEvent = msg(ts: 2000);
      // Квитанции нет вовсе → latestOwnReceipt null → ts 0 < 2000.
      expect(room.hasNewMessages, isTrue);
      expect(room.countsTowardAppBadge, isTrue);
    });

    test('AC:RL-badge-receipt-based/3 notif>0 + lastEvent==null (не оценить) → '
        'в бейдж (fail-safe: доверяем серверу)', () {
      final room = newRoom()..notificationCount = 2;
      expect(room.lastEvent, isNull);
      expect(room.countsTowardAppBadge, isTrue);
    });

    test('AC:RL-badge-receipt-based/4 notif>0 + lastEvent НЕ preview-тип '
        '(m.room.member) → в бейдж (не оценить → доверяем серверу)', () {
      final room = newRoom()
        ..notificationCount = 2
        ..lastEvent = msg(ts: 2000, type: EventTypes.RoomMember);
      // Квитанция «покрывает» ts, но тип не в roomPreviewLastEvents →
      // canEvaluateReceipt=false → консервативно считаем.
      setReceipt(room, eventId: '\$msg2000', ts: 3000);
      expect(room.countsTowardAppBadge, isTrue);
    });

    test('AC:RL-badge-receipt-based/5 notif==0 → НЕ в бейдж (muted/fully-read, '
        'поведение сохранено)', () {
      final room = newRoom()
        ..notificationCount = 0
        ..lastEvent = msg(ts: 2000);
      expect(room.countsTowardAppBadge, isFalse);
    });

    test('AC:RL-badge-receipt-based/6 markedUnread при notif==0 → в бейдж '
        '(ручная пометка независима от notif_count)', () {
      final room = newRoom()..notificationCount = 0;
      room.roomAccountData['m.marked_unread'] = BasicEvent(
        type: 'm.marked_unread',
        content: {'unread': true},
      );
      expect(room.markedUnread, isTrue);
      expect(room.countsTowardAppBadge, isTrue);
    });
  });
}
