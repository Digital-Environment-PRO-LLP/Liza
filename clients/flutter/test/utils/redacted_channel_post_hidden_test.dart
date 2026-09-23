// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';

import 'test_client.dart';

/// Страж реестра регрессии: ledger:RL-channel-redacted-post-hidden.
///
/// Удалённый пост канала обязан исчезать из ленты целиком (как в Liza),
/// независимо от пользовательской настройки `hideRedactedEvents`. В обычном
/// чате поведение остаётся дефолтным (FluffyChat): надгробие «удалено»
/// показывается, пока настройка выключена.
void main() {
  late Client client;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.hideRedactedEvents.setItem(false);
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await AppSettings.hideRedactedEvents.setItem(false);
    await client.dispose(closeDatabase: true);
  });

  Room buildRoom({required Map<String, dynamic> createContent}) {
    final room = Room(id: '!r:example.invalid', client: client);
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
    return room;
  }

  Event buildMessage(Room room, {required bool redacted}) => Event(
    eventId: '\$msg',
    senderId: '@creator:example.invalid',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
    type: EventTypes.Message,
    content: redacted
        ? <String, dynamic>{}
        : {'msgtype': MessageTypes.Text, 'body': 'привет'},
    room: room,
    unsigned: redacted
        ? {
            'redacted_because': {
              'event_id': '\$redaction',
              'sender': '@creator:example.invalid',
              'origin_server_ts': 3000,
              'type': EventTypes.Redaction,
              'redacts': '\$msg',
              'content': <String, dynamic>{},
            },
          }
        : null,
  );

  group('удалённый пост в канале', () {
    // ledger:RL-channel-redacted-post-hidden
    // AC:RL-channel-redacted-post-hidden/1
    test('НЕ попадает в filterByVisibleInGui при hideRedactedEvents=false', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': channelChatType},
      );
      expect(room.isChannel, isTrue);

      final redactedPost = buildMessage(room, redacted: true);
      expect(redactedPost.redacted, isTrue);

      expect([redactedPost].filterByVisibleInGui(), isEmpty);
      expect(redactedPost.isVisibleInGui, isFalse);
    });

    // AC:RL-channel-redacted-post-hidden/3
    test('живой пост канала остаётся видимым', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': channelChatType},
      );
      final post = buildMessage(room, redacted: false);
      expect([post].filterByVisibleInGui(), hasLength(1));
    });

    // AC:RL-channel-redacted-post-hidden/2
    test('exceptionEventId не воскрешает удалённый пост канала', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': channelChatType},
      );
      final redactedPost = buildMessage(room, redacted: true);
      expect(
        [redactedPost].filterByVisibleInGui(exceptionEventId: '\$msg'),
        isEmpty,
      );
    });
  });

  // AC:RL-channel-redacted-post-hidden/4
  group('регресс-защита: обычный чат не меняет поведение', () {
    test('удалённое сообщение видно при hideRedactedEvents=false', () {
      final room = buildRoom(createContent: {});
      expect(room.isChannel, isFalse);

      final redacted = buildMessage(room, redacted: true);
      expect(redacted.redacted, isTrue);
      expect([redacted].filterByVisibleInGui(), hasLength(1));
    });

    test('удалённое сообщение скрыто при hideRedactedEvents=true', () async {
      await AppSettings.hideRedactedEvents.setItem(true);
      final room = buildRoom(createContent: {});
      final redacted = buildMessage(room, redacted: true);
      expect([redacted].filterByVisibleInGui(), isEmpty);
    });

    test('чат-обсуждение канала — обычное поведение (надгробие видно)', () {
      final room = buildRoom(
        createContent: {'com.liza.chat.type': channelDiscussionChatType},
      );
      expect(room.isChannel, isFalse);
      final redacted = buildMessage(room, redacted: true);
      expect([redacted].filterByVisibleInGui(), hasLength(1));
    });
  });
}
