// ledger:RL-channel-feed-no-state-events
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import '../utils/test_client.dart';

Event _stateEvent(Room room, String type) => Event(
      type: type,
      eventId: '\$state_$type',
      senderId: '@alice:example.invalid',
      originServerTs: DateTime.now(),
      content: {'membership': 'join'},
      stateKey: '',
      room: room,
    );

void main() {
  group('системные события в канале', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
    });

    tearDown(() async => client.dispose());

    test('в канале member/name/avatar/topic/alias скрыты, create виден', () async {
      final room = Room(id: '!channel:example.invalid', client: client);
      room.setState(
        Event(
          type: EventTypes.RoomCreate,
          eventId: '\$create',
          senderId: '@alice:example.invalid',
          originServerTs: DateTime.now(),
          content: {'com.liza.chat.type': 'channel'},
          stateKey: '',
          room: room,
        ),
      );

      for (final type in [
        EventTypes.RoomMember,
        EventTypes.RoomName,
        EventTypes.RoomAvatar,
        EventTypes.RoomTopic,
        EventTypes.RoomCanonicalAlias,
      ]) {
        // AC:RL-channel-feed-no-state-events/1
        expect(
          _stateEvent(room, type).isHiddenChannelStateEvent,
          isTrue,
          reason: '$type должен скрываться в канале',
        );
      }

      // AC:RL-channel-feed-no-state-events/1
      expect(
        _stateEvent(room, EventTypes.RoomCreate).isHiddenChannelStateEvent,
        isFalse,
        reason: 'создание канала показываем, как в Liza',
      );
    });

    test('в обычной группе те же события остаются видимыми', () async {
      final room = Room(id: '!group:example.invalid', client: client);
      room.setState(
        Event(
          type: EventTypes.RoomCreate,
          eventId: '\$create',
          senderId: '@alice:example.invalid',
          originServerTs: DateTime.now(),
          content: const {},
          stateKey: '',
          room: room,
        ),
      );

      // AC:RL-channel-feed-no-state-events/1
      expect(
        _stateEvent(room, EventTypes.RoomMember).isHiddenChannelStateEvent,
        isFalse,
      );
    });

    test('фильтр таймлайна вырезает системные события канала', () async {
      final room = Room(id: '!channel2:example.invalid', client: client);
      room.setState(
        Event(
          type: EventTypes.RoomCreate,
          eventId: '\$create',
          senderId: '@alice:example.invalid',
          originServerTs: DateTime.now(),
          content: {'com.liza.chat.type': 'channel'},
          stateKey: '',
          room: room,
        ),
      );

      final post = Event(
        type: EventTypes.Message,
        eventId: '\$post',
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.now(),
        content: {'msgtype': 'm.text', 'body': 'пост'},
        room: room,
      );

      final filtered = [
        post,
        _stateEvent(room, EventTypes.RoomMember),
        _stateEvent(room, EventTypes.RoomAvatar),
      ].filterByVisibleInGui();

      // AC:RL-channel-feed-no-state-events/1
      expect(filtered.map((e) => e.eventId), ['\$post']);
    });
  });
}
