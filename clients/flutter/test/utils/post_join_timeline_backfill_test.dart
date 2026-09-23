// ledger:RL-post-join-timeline-backfill
// LABA-1898: после принятия приглашения сообщение, отправленное ДО join, видно
// в превью списка чатов, но не в таймлайне открытого чата. Причина: invite→join
// приходит limited-sync'ом, SDK вычищает локальную ленту (deleteTimelineForRoom)
// и восстанавливает только превью room.lastEvent серверным /messages; само
// сообщение остаётся за prev_batch-гэпом. Фикс — backfillEmptyTimelineAfterJoin:
// при пустой видимой ленте + реальном (не заглушка) lastEvent разово (с потолком
// батчей) дотягивает историю через настоящий timeline.requestHistory().
//
// Страж бьёт по РЕАЛЬНОМУ Timeline (не реплике): серверная догрузка мокается
// через FakeMatrixApi, ассерт — на фактических timeline.events.
//
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

import 'package:liza/utils/post_join_backfill.dart';

import 'test_client.dart';

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await client.dispose(closeDatabase: true);
  });

  // Ключ маршрута FakeMatrixApi для requestHistory (Direction.b): экранированный
  // roomId + from=prev_batch, dir=b, limit, filter={"lazy_load_members":true}.
  String messagesRoute(String roomId, String from, int limit) {
    final enc = Uri.encodeComponent(roomId);
    return '/client/v3/rooms/$enc/messages?from=$from&dir=b&limit=$limit'
        '&filter=%7B%22lazy_load_members%22%3Atrue%7D';
  }

  Map<String, Object?> msgJson(
    String roomId,
    String eventId,
    String body, {
    int ts = 2000,
  }) => {
    'type': EventTypes.Message,
    'content': {'msgtype': 'm.text', 'body': body},
    'event_id': eventId,
    'room_id': roomId,
    'sender': '@author:example.invalid',
    'origin_server_ts': ts,
  };

  Event lastEventStub(Room room, {String? type}) => Event(
    type: type ?? EventTypes.Message,
    eventId: '\$last:example.invalid',
    senderId: '@author:example.invalid',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
    room: room,
    content: type == EventTypes.refreshingLastEvent
        ? const {}
        : const {'msgtype': 'm.text', 'body': 'до-join сообщение'},
  );

  Room joinedRoom(
    String id, {
    String? prevBatch,
    Event? Function(Room)? lastEvent,
    Membership membership = Membership.join,
    bool direct = false,
  }) {
    final room = Room(id: id, client: client, membership: membership);
    if (prevBatch != null) room.prev_batch = prevBatch;
    room.lastEvent = lastEvent?.call(room);
    client.rooms.add(room);
    return room;
  }

  group('LABA-1898 backfillEmptyTimelineAfterJoin', () {
    // AC:RL-post-join-timeline-backfill/1
    test('AC-1: пустая лента + реальный lastEvent → догрузка дотягивает сообщение',
        () async {
      const roomId = '!ac1:example.invalid';
      final room = joinedRoom(
        roomId,
        prevBatch: 'p1',
        lastEvent: (r) => lastEventStub(r),
      );
      FakeMatrixApi.currentApi!.api['GET']![messagesRoute(roomId, 'p1', 100)] =
          (_) => {
        'start': 'p1',
        'end': 'p2',
        'chunk': [msgJson(roomId, '\$m1', 'до-join сообщение')],
        'state': <Map<String, Object?>>[],
      };

      final timeline = await room.getTimeline();
      // До фикса именно тут пусто (регресс-инвариант).
      expect(
        timeline.events.where((e) => e.type == EventTypes.Message).isEmpty,
        isTrue,
        reason: 'исходная лента после limited-sync пуста',
      );

      final batches = await backfillEmptyTimelineAfterJoin(
        timeline,
        isMounted: () => true,
        historyCount: 100,
      );

      expect(batches, 1, reason: 'ровно один разовый requestHistory');
      expect(
        timeline.events.any((e) => e.body == 'до-join сообщение'),
        isTrue,
        reason: 'после догрузки до-join сообщение обязано быть в ленте',
      );
    });

    // AC:RL-post-join-timeline-backfill/2
    test('AC-2: механизм одинаков для DM и группы (direct-agnostic)', () async {
      for (final direct in [true, false]) {
        final roomId = '!ac2_$direct:example.invalid';
        final room = joinedRoom(
          roomId,
          prevBatch: 'p1',
          direct: direct,
          lastEvent: (r) => lastEventStub(r),
        );
        FakeMatrixApi.currentApi!.api['GET']![messagesRoute(roomId, 'p1', 100)] =
            (_) => {
          'start': 'p1',
          'end': 'p2',
          'chunk': [msgJson(roomId, '\$m_$direct', 'сообщение $direct')],
          'state': <Map<String, Object?>>[],
        };

        final timeline = await room.getTimeline();
        final batches = await backfillEmptyTimelineAfterJoin(
          timeline,
          isMounted: () => true,
          historyCount: 100,
        );

        expect(batches, 1, reason: 'direct=$direct: одна догрузка');
        expect(
          timeline.events.any((e) => e.body == 'сообщение $direct'),
          isTrue,
          reason: 'direct=$direct: сообщение в ленте',
        );
      }
    });

    // AC:RL-post-join-timeline-backfill/3
    test('AC-3: реально пустой чат (lastEvent==null) → НЕ дёргаем сеть', () async {
      const roomId = '!ac3:example.invalid';
      final room = joinedRoom(roomId, prevBatch: 'p1'); // lastEvent == null
      // Маршрут /messages НЕ зарегистрирован — если фикс ошибочно дёрнет сеть,
      // FakeMatrixApi бросит и тест упадёт.
      final timeline = await room.getTimeline();

      final batches = await backfillEmptyTimelineAfterJoin(
        timeline,
        isMounted: () => true,
        historyCount: 100,
      );

      expect(batches, 0, reason: 'без сообщения (lastEvent==null) догрузки нет');
      expect(timeline.events, isEmpty);
    });

    // AC:RL-post-join-timeline-backfill/4
    test('AC-4: обычный чат с историей → лишней догрузки нет', () async {
      const roomId = '!ac4:example.invalid';
      final room = joinedRoom(
        roomId,
        prevBatch: 'p1',
        lastEvent: (r) => lastEventStub(r),
      );
      // Непустая лента (реальные события уже загружены).
      final existing = Event(
        type: EventTypes.Message,
        eventId: '\$exists:example.invalid',
        senderId: '@author:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        room: room,
        content: const {'msgtype': 'm.text', 'body': 'уже в ленте'},
      );
      final timeline =
          Timeline(room: room, chunk: TimelineChunk(events: [existing]));

      final batches = await backfillEmptyTimelineAfterJoin(
        timeline,
        isMounted: () => true,
        historyCount: 100,
      );

      expect(batches, 0, reason: 'видимая лента непуста → триггер не срабатывает');
    });

    // AC:RL-post-join-timeline-backfill/5
    test('AC-5: несколько до-join сообщений подтягиваются одной догрузкой',
        () async {
      const roomId = '!ac5:example.invalid';
      final room = joinedRoom(
        roomId,
        prevBatch: 'p1',
        lastEvent: (r) => lastEventStub(r),
      );
      FakeMatrixApi.currentApi!.api['GET']![messagesRoute(roomId, 'p1', 100)] =
          (_) => {
        'start': 'p1',
        'end': 'p2',
        'chunk': [
          msgJson(roomId, '\$m3', 'третье', ts: 2003),
          msgJson(roomId, '\$m2', 'второе', ts: 2002),
          msgJson(roomId, '\$m1', 'первое', ts: 2001),
        ],
        'state': <Map<String, Object?>>[],
      };

      final timeline = await room.getTimeline();
      final batches = await backfillEmptyTimelineAfterJoin(
        timeline,
        isMounted: () => true,
        historyCount: 100,
      );

      expect(batches, 1);
      final bodies = timeline.events.map((e) => e.body).toSet();
      expect(bodies.containsAll({'первое', 'второе', 'третье'}), isTrue,
          reason: 'все до-join сообщения в ленте');
    });

    // AC:RL-post-join-timeline-backfill/6
    test('AC-6: заглушка refreshingLastEvent → догрузки нет (не реальное событие)',
        () async {
      const roomId = '!ac6:example.invalid';
      final room = joinedRoom(
        roomId,
        prevBatch: 'p1',
        lastEvent: (r) =>
            lastEventStub(r, type: EventTypes.refreshingLastEvent),
      );
      // Маршрут не зарегистрирован — преждевременная догрузка на заглушке упадёт.
      final timeline = await room.getTimeline();

      final batches = await backfillEmptyTimelineAfterJoin(
        timeline,
        isMounted: () => true,
        historyCount: 100,
      );

      expect(batches, 0,
          reason: 'lastEvent — фейк-заглушка, реального сообщения ещё нет');
    });

    // AC:RL-post-join-timeline-backfill/7
    test('AC-7: сервер молчит → цикл ограничен потолком, без зацикливания',
        () async {
      const roomId = '!ac7:example.invalid';
      final room = joinedRoom(
        roomId,
        prevBatch: 'p1',
        lastEvent: (r) => lastEventStub(r),
      );
      // Сервер всегда отдаёт пустой чанк с тем же end → лента остаётся пустой,
      // canRequestHistory остаётся true. Фикс обязан упереться в maxBatches.
      FakeMatrixApi.currentApi!.api['GET']![messagesRoute(roomId, 'p1', 100)] =
          (_) => {
        'start': 'p1',
        'end': 'p1',
        'chunk': <Map<String, Object?>>[],
        'state': <Map<String, Object?>>[],
      };

      final timeline = await room.getTimeline();
      final batches = await backfillEmptyTimelineAfterJoin(
        timeline,
        isMounted: () => true,
        maxBatches: 3,
        historyCount: 100,
      );

      expect(batches, 3, reason: 'ровно потолок батчей, не бесконечный цикл');
      expect(timeline.events.where((e) => e.type == EventTypes.Message),
          isEmpty);
    });

    test('membership != join → догрузки нет (peek/не-член, красная линия)',
        () async {
      const roomId = '!ac8:example.invalid';
      final room = joinedRoom(
        roomId,
        prevBatch: 'p1',
        membership: Membership.invite,
        lastEvent: (r) => lastEventStub(r),
      );
      final timeline = await room.getTimeline();

      final batches = await backfillEmptyTimelineAfterJoin(
        timeline,
        isMounted: () => true,
        historyCount: 100,
      );

      expect(batches, 0,
          reason: 'canRequestHistory=false при membership!=join/leave');
    });
  });
}
