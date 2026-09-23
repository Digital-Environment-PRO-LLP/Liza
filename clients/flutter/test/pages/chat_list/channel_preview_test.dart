// ledger:RL-channel-list-preview-clean
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/pages/chat_list/chat_list_item.dart';
import '../../utils/test_client.dart';

void main() {
  group('превью канала в списке чатов', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
    });

    tearDown(() async => client.dispose());

    Room channelRoom() {
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
      return room;
    }

    test('системное событие в хвосте не становится превью', () {
      final room = channelRoom();
      final post = Event(
        type: EventTypes.Message,
        eventId: '\$post',
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        content: {'msgtype': 'm.text', 'body': 'пост'},
        room: room,
      );
      final avatarChange = Event(
        type: EventTypes.RoomAvatar,
        eventId: '\$avatar',
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
        content: const {'url': 'mxc://x/y'},
        stateKey: '',
        room: room,
      );

      // AC:RL-channel-list-preview-clean/2
      expect(
        previewEventFrom([avatarChange, post])?.eventId,
        '\$post',
        reason: 'превью показывает последний пост, а не смену аватара',
      );
    });

    test('удалённый пост канала не становится превью', () {
      final room = channelRoom();
      final redacted = Event(
        type: EventTypes.Message,
        eventId: '\$redacted',
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(3000),
        content: const {},
        room: room,
        unsigned: {
          'redacted_because': {
            'type': 'm.room.redaction',
            'event_id': '\$redaction',
            'sender': '@alice:example.invalid',
            'origin_server_ts': 3500,
            'content': <String, dynamic>{},
          },
        },
      );
      final post = Event(
        type: EventTypes.Message,
        eventId: '\$post',
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        content: {'msgtype': 'm.text', 'body': 'пост'},
        room: room,
      );

      // AC:RL-channel-list-preview-clean/2
      expect(previewEventFrom([redacted, post])?.eventId, '\$post');
    });

    test('если пригодных событий нет — превью пустое', () {
      final room = channelRoom();
      final avatarChange = Event(
        type: EventTypes.RoomAvatar,
        eventId: '\$avatar',
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.now(),
        content: const {'url': 'mxc://x/y'},
        stateKey: '',
        room: room,
      );

      // AC:RL-channel-list-preview-clean/2
      expect(previewEventFrom([avatarChange]), isNull);
    });
  });
}
