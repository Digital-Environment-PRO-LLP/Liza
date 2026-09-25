// LABA-2624: превью удалённого последнего сообщения в списке чатов рисовалось
// зачёркнутым и врало текстом («X отредактировал это событие» — redact
// переведён как «отредактировать», а в имя подставлялся АВТОР сообщения, а не
// тот, кто удалил). Проверяем на РЕАЛЬНОМ ChatListItem.
//
// ledger:RL-chat-list-redacted-preview

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/chat_list_item.dart';
import 'package:liza/widgets/matrix.dart';

import '../../utils/test_client.dart';

const _author = '@author:example.invalid';
const _moderator = '@moderator:example.invalid';
const _partner = '@partner:example.invalid';

void main() {
  late Client client;
  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    client.backgroundSync = false;
    store = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  Event member(Room room, String mxid, String name) => Event(
    eventId: '\$m-$mxid',
    senderId: mxid,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    type: EventTypes.RoomMember,
    content: {'membership': 'join', 'displayname': name},
    room: room,
    stateKey: mxid,
  );

  /// Комната, последнее событие которой — сообщение [_author], удалённое
  /// [redactor] (или живое, если [redactor] == null). [direct] — DM с [_author].
  Room buildRoom({String? redactor, bool direct = false}) {
    final roomId = direct ? '!dm:example.invalid' : '!group:example.invalid';
    final room = Room(id: roomId, client: client);
    client.rooms.add(room);
    room.setState(member(room, _author, 'Автор Сообщения'));
    room.setState(member(room, _moderator, 'Модератор Чата'));
    if (direct) {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          _author: [roomId],
        },
      );
    } else {
      room.setState(member(room, _partner, 'Третий Участник'));
      room.setState(
        Event(
          eventId: '\$name',
          senderId: _author,
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: EventTypes.RoomName,
          content: const {'name': 'Группа'},
          room: room,
          stateKey: '',
        ),
      );
    }
    room.lastEvent = Event(
      eventId: '\$msg',
      senderId: _author,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
      type: EventTypes.Message,
      content: redactor == null
          ? const {'msgtype': 'm.text', 'body': 'живое сообщение'}
          : const {},
      unsigned: redactor == null
          ? null
          : {
              'redacted_because': {
                'type': EventTypes.Redaction,
                'event_id': '\$redaction',
                'sender': redactor,
                'origin_server_ts': 3000,
                'redacts': '\$msg',
                'content': const <String, Object?>{},
              },
            },
      room: room,
    );
    return room;
  }

  Future<void> pump(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Matrix(
          clients: [client],
          store: store,
          child: Scaffold(body: ChatListItem(room, onTap: () {})),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Text previewText(WidgetTester tester, String contains) {
    final finder = find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains(contains),
    );
    expect(finder, findsOneWidget, reason: 'превью с «$contains» не найдено');
    return tester.widget<Text>(finder);
  }

  // Строка группы заводит отложенный таймер (подгрузка участников) —
  // размонтируем и даём ему отработать, иначе «Timer is still pending».
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  for (final direct in [false, true]) {
    final kind = direct ? 'DM' : 'группа';

    testWidgets('$kind: удалённое последнее сообщение — без зачёркивания, '
        'имя удалившего AC:RL-chat-list-redacted-preview/1 '
        'AC:RL-chat-list-redacted-preview/2', (tester) async {
      await pump(tester, buildRoom(redactor: _moderator, direct: direct));

      final text = previewText(tester, 'Удалено пользователем');
      expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
      expect(text.data, contains('Модератор Чата'));
      expect(text.data, isNot(contains('Автор Сообщения')));
      expect(text.data, isNot(contains('отредактир')));
      await unmount(tester);
    });

    testWidgets(
      '$kind: обычное превью без decoration AC:RL-chat-list-redacted-preview/4',
      (tester) async {
        await pump(tester, buildRoom(direct: direct));

        final text = previewText(tester, 'живое сообщение');
        expect(text.style?.decoration, isNull);
        await unmount(tester);
      },
    );
  }

  test('ru-переводы удаления не говорят «редактировать» '
      'AC:RL-chat-list-redacted-preview/3', () {
    final ru =
        jsonDecode(File('lib/l10n/intl_ru.arb').readAsStringSync())
            as Map<String, dynamic>;
    for (final key in const [
      'redactedBy',
      'redactedByBecause',
      'removedBy',
      'hideRedactedEvents',
      'hideRedactedMessages',
      'hideRedactedMessagesBody',
    ]) {
      final value = ru[key] as String?;
      expect(value, isNotNull, reason: '$key отсутствует в intl_ru.arb');
      expect(
        value!.toLowerCase(),
        isNot(contains('редактир')),
        reason: '$key: redact = удалить, а не редактировать',
      );
    }
  });
}
