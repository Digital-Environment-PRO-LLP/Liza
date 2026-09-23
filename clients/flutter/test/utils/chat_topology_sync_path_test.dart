// ledger:RL-discussion-hidden-on-sync
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';
import 'test_client.dart';

void main() {
  group('топология доезжает через sync (partial-комната)', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
    });

    tearDown(() async => client.dispose());

    test(
      'чат обсуждений скрыт сразу после sync, без открытия таймлайна',
      () async {
        const roomId = '!discussion:example.invalid';

        await client.handleSync(
          SyncUpdate(
            nextBatch: 'batch1',
            rooms: RoomsUpdate(
              join: {
                roomId: JoinedRoomUpdate(
                  state: [
                    MatrixEvent(
                      type: EventTypes.RoomCreate,
                      eventId: '\$create',
                      senderId: '@alice:example.invalid',
                      originServerTs: DateTime.now(),
                      content: {'com.liza.chat.type': 'channel_discussion'},
                      stateKey: '',
                    ),
                    MatrixEvent(
                      type: 'com.liza.chat.topology',
                      eventId: '\$topology',
                      senderId: '@alice:example.invalid',
                      originServerTs: DateTime.now(),
                      content: const {'hidden': true},
                      stateKey: '',
                    ),
                  ],
                ),
              },
            ),
          ),
        );

        // AC:RL-discussion-hidden-on-sync/1
        final room = client.getRoomById(roomId);
        expect(room, isNotNull, reason: 'комната должна приехать из sync');
        expect(
          room!.partial,
          isTrue,
          reason:
              'таймлайн не открывали — комната остаётся partial, '
              'именно этот путь ломал скрытие',
        );
        expect(
          room.getState('com.liza.chat.topology'),
          isNotNull,
          reason: 'топология обязана пережить гейт importantStateEvents',
        );
        expect(
          room.isHiddenChat,
          isTrue,
          reason: 'чат обсуждений не должен попадать в список чатов',
        );
      },
    );
  });
}
