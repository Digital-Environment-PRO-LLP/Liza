// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

import 'test_client.dart';

const _topologyEventType = 'com.liza.chat.topology';

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!r:example.invalid', client: client);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  Room buildRoom({
    required Map<String, dynamic> createContent,
    Map<String, dynamic>? topologyContent,
  }) {
    room.setState(
      Event(
        eventId: '\$create',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomCreate,
        content: createContent,
        room: room,
        stateKey: '',
      ),
    );
    if (topologyContent != null) {
      room.setState(
        Event(
          eventId: '\$topology',
          senderId: '@creator:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: _topologyEventType,
          content: topologyContent,
          room: room,
          stateKey: '',
        ),
      );
    }
    return room;
  }

  Room buildRoomWithCreateContent(Map<String, dynamic> createContent) =>
      buildRoom(createContent: createContent);

  void setRevealedAccountData(Room room, Map<String, Object?> content) {
    room.roomAccountData[chatRevealedAccountDataType] = BasicEvent(
      type: chatRevealedAccountDataType,
      content: content,
    );
  }

  group('LizaChatTopology', () {
    test('lizaChatType returns null for room without type markers', () {
      final room = buildRoomWithCreateContent({});
      expect(room.lizaChatType, isNull);
    });

    test('lizaChatType returns stories for new key com.liza.chat.type', () {
      final room =
          buildRoomWithCreateContent({'com.liza.chat.type': 'stories'});
      expect(room.lizaChatType, 'stories');
    });

    test('lizaChatType returns stories for legacy key com.liza.stories', () {
      final room = buildRoomWithCreateContent({'com.liza.stories': true});
      expect(room.lizaChatType, 'stories');
    });

    test('lizaChatType prefers new key when both present', () {
      final room = buildRoomWithCreateContent({
        'com.liza.stories': true,
        'com.liza.chat.type': 'stories',
      });
      expect(room.lizaChatType, 'stories');
    });

    test('isHiddenChat false for non-stories room without topology state', () {
      final room = buildRoom(createContent: {}, topologyContent: null);
      expect(room.isHiddenChat, isFalse);
    });

    test(
      'isHiddenChat true for stories room without topology state (legacy default)',
      () {
        final room = buildRoom(
          createContent: {'com.liza.stories': true},
          topologyContent: null,
        );
        expect(room.isHiddenChat, isTrue);
      },
    );

    test('isHiddenChat reads explicit hidden:true from topology state', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': 'stories'},
        topologyContent: {'hidden': true},
      );
      expect(room.isHiddenChat, isTrue);
    });

    test('isHiddenChat reads explicit hidden:false from topology state', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': 'stories'},
        topologyContent: {'hidden': false},
      );
      expect(room.isHiddenChat, isFalse);
    });

    test('isHiddenChat false for plain room with no type and no topology state', () {
      final room = buildRoom(createContent: {}, topologyContent: null);
      expect(room.isHiddenChat, isFalse);
    });
  });

  group('персональное раскрытие чата (account data)', () {
    test('без account data чат-обсуждение с hidden:true скрыт', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': channelDiscussionChatType},
        topologyContent: {'hidden': true},
      );
      expect(room.isRevealedByMe, isFalse);
      expect(room.isHiddenChat, isTrue);
    });

    test('revealed:true раскрывает чат, несмотря на room-state hidden:true', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': channelDiscussionChatType},
        topologyContent: {'hidden': true},
      );
      setRevealedAccountData(room, {'revealed': true});
      expect(room.isRevealedByMe, isTrue);
      expect(room.isHiddenChat, isFalse);
    });

    test('revealed:false не раскрывает — скрытость по room-state остаётся', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': channelDiscussionChatType},
        topologyContent: {'hidden': true},
      );
      setRevealedAccountData(room, {'revealed': false});
      expect(room.isRevealedByMe, isFalse);
      expect(room.isHiddenChat, isTrue);
    });

    test('раскрытие перекрывает и легаси-скрытость сторис-комнаты', () {
      final room = buildRoom(
        createContent: {'com.liza.stories': true},
        topologyContent: null,
      );
      expect(room.isHiddenChat, isTrue);
      setRevealedAccountData(room, {'revealed': true});
      expect(room.isHiddenChat, isFalse);
    });

    test('раскрытие не делает скрытым обычный видимый чат', () {
      final room = buildRoom(createContent: {}, topologyContent: null);
      setRevealedAccountData(room, {'revealed': true});
      expect(room.isHiddenChat, isFalse);
    });
  });

  // Регресс фантомного бейджа на иконке (macOS «1» без непрочитанных в списке):
  // скрытые (stories/topology-hidden) комнаты с notificationCount не должны
  // идти в счётчик бейджа — их нельзя открыть и прочитать.
  // Страж реестра регрессии: ledger:RL-app-badge-visible-rooms-only.
  group('countsTowardAppBadge', () {
    test('visible unread room counts toward badge', () {
      final room = buildRoom(createContent: {}, topologyContent: null)
        ..notificationCount = 1;
      expect(room.isHiddenChat, isFalse);
      expect(room.isUnread, isTrue);
      expect(room.countsTowardAppBadge, isTrue);
    });

    test('hidden stories room does NOT count toward badge even when unread', () {
      final room = buildRoom(
        createContent: {'com.liza.stories': true},
        topologyContent: null,
      )..notificationCount = 3;
      expect(room.isHiddenChat, isTrue);
      expect(room.isUnread, isTrue);
      expect(room.countsTowardAppBadge, isFalse);
    });

    test('topology-hidden room does NOT count toward badge even when unread', () {
      final room = buildRoom(
        createContent: {},
        topologyContent: {'hidden': true},
      )..notificationCount = 2;
      expect(room.isHiddenChat, isTrue);
      expect(room.countsTowardAppBadge, isFalse);
    });

    test('visible read room does not count toward badge', () {
      final room = buildRoom(createContent: {}, topologyContent: null)
        ..notificationCount = 0;
      expect(room.countsTowardAppBadge, isFalse);
    });

    test('topology-visible stories room counts when unread', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': 'stories'},
        topologyContent: {'hidden': false},
      )..notificationCount = 1;
      expect(room.isHiddenChat, isFalse);
      expect(room.countsTowardAppBadge, isTrue);
    });
  });
}
