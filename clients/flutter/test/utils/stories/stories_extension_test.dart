// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/stories/stories_extension.dart';

import 'test_client.dart';

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  test(
    'ensureMyStoriesRoom sends both type keys, atomic hidden state, PL gate',
    () async {
      Map<String, dynamic>? capturedBody;
      final fakeApi = FakeMatrixApi.currentApi!;
      FakeMatrixApi.client = client;
      final original = fakeApi.api['POST']!['/client/v3/createRoom']!;
      fakeApi.api['POST']!['/client/v3/createRoom'] = (req) {
        capturedBody = jsonDecode(req as String) as Map<String, dynamic>;
        final res = original(req) as Map<String, dynamic>;
        // FakeMatrixApi не проталкивает новую комнату через sync сама -
        // ensureMyStoriesRoom после createRoom делает getRoomById и без
        // этого уходит в waitForRoomInSync, который никогда не разрешится.
        client.rooms = [
          ...client.rooms,
          Room(id: res['room_id'] as String, client: client),
        ];
        return res;
      };

      final room = await client.ensureMyStoriesRoom();

      // Без этого ensureMyStoriesRoom повторно создаст комнату при будущих
      // вызовах в этом тесте: getRoomById ищет в client.rooms, а
      // FakeMatrixApi не проталкивает созданную комнату через sync сама.
      expect(room.id, isNotEmpty);

      expect(capturedBody, isNotNull);
      // Имя уникально по localpart владельца (было хардкожено 'Stories' у
      // всех - неразличимо в админке/логах, см. RL-stories-ttl-window).
      // FakeMatrixApi логинит как @test:..., несмотря на identifier alice
      // в client.login (см. test_client.dart) - берём фактический userID.
      expect(capturedBody!['name'], 'Stories - ${client.userID!.localpart}');
      expect(
        capturedBody!['creation_content'],
        {
          'com.liza.stories': true,
          'com.liza.chat.type': 'stories',
        },
      );

      final initialState =
          (capturedBody!['initial_state'] as List).cast<Map<String, dynamic>>();
      expect(
        initialState.any(
          (e) =>
              e['type'] == 'com.liza.chat.topology' &&
              (e['content'] as Map)['hidden'] == true,
        ),
        isTrue,
      );

      final plOverride =
          capturedBody!['power_level_content_override'] as Map<String, dynamic>;
      expect(
        (plOverride['events'] as Map)['com.liza.chat.topology'],
        100,
      );
    },
  );

  // ledger:RL-stories-own-ring-opens-own
  test(
    'storyOwnerOf returns my own userID for my room even with another participant',
    () async {
      final myRoom = Room(
        id: '!myStories:example.invalid',
        client: client,
      );
      myRoom.setState(
        Event(
          type: EventTypes.RoomCreate,
          eventId: r'$create1',
          content: {'creator': client.userID},
          senderId: client.userID!,
          originServerTs: DateTime.now(),
          room: myRoom,
          stateKey: '',
        ),
      );
      myRoom.setState(
        Event(
          type: EventTypes.RoomMember,
          eventId: r'$member1',
          content: {'membership': 'join'},
          senderId: '@stranger:example.invalid',
          originServerTs: DateTime.now(),
          room: myRoom,
          stateKey: '@stranger:example.invalid',
        ),
      );

      expect(client.storyOwnerOf(myRoom), client.userID);
    },
  );

  // ledger:RL-stories-own-ring-opens-own
  test(
    'storyOwnerOf falls back to other participant only when creator is unknown',
    () async {
      final room = Room(id: '!noCreator:example.invalid', client: client);
      room.setState(
        Event(
          type: EventTypes.RoomMember,
          eventId: r'$member2',
          content: {'membership': 'join'},
          senderId: '@author:example.invalid',
          originServerTs: DateTime.now(),
          room: room,
          stateKey: '@author:example.invalid',
        ),
      );

      expect(client.storyOwnerOf(room), '@author:example.invalid');
    },
  );

  // ledger:RL-stories-ttl-window
  // Баг на prod: флуд повторных m.room.redaction (до 670 на одно событие,
  // см. servers/synapse/modules/stories_membership) засорял таймлайн
  // сторис-комнаты мусорными событиями. activeStoriesOf вызывал
  // room.getTimeline() без явного limit -> SDK-дефолт Room.defaultHistoryCount
  // (30) вытеснял ещё живой (не истёкший) сториc за пределы окна пагинации,
  // хотя expires_ts в БД оставался корректным. Тест воспроизводит это без
  // сервера: одно живое сториc-сообщение + 40 последующих обычных сообщений
  // в той же комнате (достаточно, чтобы превысить дефолтный лимит в 30).
  test(
    'activeStoriesOf finds a still-active story pushed out of the default '
    'history window by later room traffic',
    () async {
      const roomId = '!flood:example.invalid';
      final room = Room(id: roomId, client: client);
      client.rooms = [...client.rooms, room];

      final now = DateTime.now().millisecondsSinceEpoch;
      final storyEvent = MatrixEvent.fromJson({
        'type': 'm.room.message',
        'content': {
          'msgtype': 'm.image',
          'com.liza.story': {'expires_ts': now + 3600000, 'overlays': []},
        },
        'sender': '@author:example.invalid',
        'status': EventStatus.synced.intValue,
        'event_id': r'$story1',
        'origin_server_ts': now - 40000,
      });
      final noise = List.generate(
        40,
        (i) => MatrixEvent.fromJson({
          'type': 'm.room.message',
          'content': {'msgtype': 'm.text', 'body': 'noise $i'},
          'sender': '@author:example.invalid',
          'status': EventStatus.synced.intValue,
          'event_id': '\$noise$i',
          'origin_server_ts': now - 39000 + i * 1000,
        }),
      );

      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch1',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                timeline: TimelineUpdate(events: [storyEvent, ...noise]),
              ),
            },
          ),
        ),
      );

      final active = await client.activeStoriesOf(room);

      expect(active.map((e) => e.eventId), contains(r'$story1'));
    },
  );
}
