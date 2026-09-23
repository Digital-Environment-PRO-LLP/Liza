// ledger:RL-channel-peek-live-feed
// AC:RL-channel-peek-live-feed/6
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/channel_discussion.dart';
import 'package:liza/utils/channel_peek.dart';
import 'package:liza/utils/chat_topology.dart';
import 'test_client.dart';

MatrixEvent _msg(String id, String body) => MatrixEvent(
      type: EventTypes.Message,
      eventId: id,
      senderId: '@author:example.invalid',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      content: {'msgtype': 'm.text', 'body': body},
    );

void main() {
  group('peek-комната и конвертация событий', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
    });

    tearDown(() async => client.dispose());

    test('синтетическая комната НЕ попадает в список комнат клиента', () {
      final before = client.rooms.length;
      final room = buildPeekRoom(client, '!channel:example.invalid');

      expect(room.id, '!channel:example.invalid');
      expect(
        room.membership,
        Membership.leave,
        reason: 'leave разрешает requestHistory (timeline.dart:81-83)',
      );
      expect(
        client.rooms.length,
        before,
        reason: 'иначе канал появится в списке чатов — ровно то, что чиним',
      );
    });

    test('MatrixEvent конвертируется в Event с непустой комнатой', () {
      final room = buildPeekRoom(client, '!channel:example.invalid');
      final events = peekEventsToTimeline([_msg('\$a', 'пост')], room);

      expect(events, hasLength(1));
      expect(events.first.eventId, '\$a');
      expect(events.first.body, 'пост');
      expect(
        events.first.room.id,
        '!channel:example.invalid',
        reason: 'Message/MessageContent требуют непустой event.room',
      );
    });

    test('presence и прочий не-комнатный шум отфильтрован', () {
      final room = buildPeekRoom(client, '!channel:example.invalid');
      final presence = MatrixEvent(
        type: 'm.presence',
        eventId: '\$p',
        senderId: '@x:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        content: const {'presence': 'online'},
      );

      final events = peekEventsToTimeline([presence, _msg('\$a', 'пост')], room);

      expect(
        events.map((e) => e.eventId),
        ['\$a'],
        reason: 'peekEvents отдаёт ВСЕ типы, включая m.presence',
      );
    });
  });

  group('state синтетической комнаты', () {
    late Client client;

    // `/rooms/{id}/state` работает и для неучастника открытого канала
    // (проверено на проде: HTTP 200, 19 событий). Отдаём урезанный, но
    // реалистичный набор: тип канала, имя и привязанный чат обсуждения.
    const roomId = '!channel:example.invalid';
    // Ключ маршрута FakeMatrixApi — это `путь?query` фактического запроса:
    // `!` не кодируется, `:` кодируется, а у /messages в ключ входят и
    // параметры пагинации.
    const statePath = '/client/v3/rooms/!channel%3Aexample.invalid/state';
    const messagesPath =
        '/client/v3/rooms/!channel%3Aexample.invalid/messages?dir=b&limit=100';

    Map<String, Object?> stateEvent(
      String type,
      Map<String, Object?> content,
    ) => {
      'type': type,
      'content': content,
      'event_id': '\$state_$type',
      'room_id': roomId,
      'sender': '@owner:example.invalid',
      'origin_server_ts': 1000,
      'state_key': '',
    };

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      final api = FakeMatrixApi.currentApi!;
      api.api['GET']![statePath] = (_) => [
        stateEvent('m.room.create', {
          'creator': '@owner:example.invalid',
          'com.liza.chat.type': channelChatType,
        }),
        stateEvent('m.room.name', {'name': 'Канал про Liza'}),
        stateEvent(channelDiscussionState, {
          'room_id': '!discussion:example.invalid',
        }),
      ];
    });

    tearDown(() async => client.dispose());

    test('после снимка комната распознаётся как канал с комментариями',
        () async {
      final api = FakeMatrixApi.currentApi!;
      api.api['GET']![messagesPath] = (_) => {
        'start': 's0',
        'end': 's1',
        'chunk': [
          {
            'type': EventTypes.Message,
            'content': {'msgtype': 'm.text', 'body': 'пост канала'},
            'event_id': '\$post',
            'room_id': roomId,
            'sender': '@owner:example.invalid',
            'origin_server_ts': 2000,
          },
        ],
      };

      final snapshot = await loadChannelPeekSnapshot(client, roomId);

      expect(snapshot, isNotNull);
      // Без заполнения state обе проверки ложны, и канал рисуется как обычный
      // чат: нет строки статистики поста, нет плашки комментариев (AC-6),
      // посты владельца уезжают вправо синими.
      expect(
        snapshot!.room.isChannel,
        isTrue,
        reason: 'm.room.create с com.liza.chat.type обязан доехать в state',
      );
      expect(
        snapshot.room.hasComments,
        isTrue,
        reason: 'без com.liza.channel.discussion плашки комментариев нет вовсе',
      );
      expect(
        snapshot.room.getLocalizedDisplayname(),
        'Канал про Liza',
        reason: 'иначе в шапке окажется room-id вместо имени канала',
      );
      expect(snapshot.events.map((e) => e.body), ['пост канала']);
    });

    test('отказ /state не роняет ленту — peek деградирует, но живёт', () async {
      final api = FakeMatrixApi.currentApi!;
      api.api['GET']![statePath] =
          (_) => throw Exception('нет доступа к состоянию');
      api.api['GET']![messagesPath] = (_) => {
        'start': 's0',
        'end': 's1',
        'chunk': [
          {
            'type': EventTypes.Message,
            'content': {'msgtype': 'm.text', 'body': 'пост канала'},
            'event_id': '\$post',
            'room_id': roomId,
            'sender': '@owner:example.invalid',
            'origin_server_ts': 2000,
          },
        ],
      };

      final snapshot = await loadChannelPeekSnapshot(client, roomId);

      expect(
        snapshot,
        isNotNull,
        reason: 'лента важнее оформления: без state показываем деградированно',
      );
      expect(snapshot!.events.map((e) => e.body), ['пост канала']);
      expect(snapshot.room.isChannel, isFalse);
    });
  });
}
