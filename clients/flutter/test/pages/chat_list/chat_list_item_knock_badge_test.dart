// Бейдж счётчика заявок на вступление (knock) в списке чатов — на РЕАЛЬНОМ
// ChatListItem, а не на реплике: countKnocking покрыт отдельно
// (test/utils/knock_requests_test.dart), но чистая функция не доказывает, что
// бейдж дошёл до экрана, скрыт у бессильного и НЕ утёк всем в компании (space,
// invite:0) — ровно тот класс, где сломанный гейт room.canInvite показал бы
// бейдж каждому участнику.
//
// ledger:RL-knock-requests

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/chat_list_item.dart';
import 'package:liza/widgets/matrix.dart';

import '../../utils/test_client.dart';

void main() {
  late Client client;
  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    // Фоновый sync-цикл держит таймер живым и роняет тест на
    // «A Timer is still pending even after the widget tree was disposed».
    client.backgroundSync = false;
    store = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  /// Комната с [knocking] заявками. [ownPowerLevel] 100 — админ, 0 — рядовой.
  /// [inviteLevel] — порог invite в power_levels (50 у групп, 0 у компаний).
  /// [isSpace] — компания/пространство (creation_content m.space).
  Room buildRoom({
    required int knocking,
    required int ownPowerLevel,
    int inviteLevel = 50,
    bool isSpace = false,
  }) {
    final room = Room(id: '!r:example.invalid', client: client);
    room.setState(
      Event(
        eventId: '\$create',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomCreate,
        content: {
          'creator': '@creator:example.invalid',
          if (isSpace) 'type': 'm.space',
        },
        room: room,
        stateKey: '',
      ),
    );
    room.setState(
      Event(
        eventId: '\$pl',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomPowerLevels,
        content: {
          'invite': inviteLevel,
          'users': {client.userID: ownPowerLevel},
        },
        room: room,
        stateKey: '',
      ),
    );
    for (var i = 0; i < knocking; i++) {
      room.setState(
        Event(
          eventId: '\$knock$i',
          senderId: '@knocker$i:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: EventTypes.RoomMember,
          content: const {'membership': 'knock'},
          room: room,
          stateKey: '@knocker$i:example.invalid',
        ),
      );
    }
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
          child: Scaffold(
            body: ChatListItem(room, onTap: () {}),
          ),
        ),
      ),
    );
    // Matrix отдаёт child не сразу (async init), а бейдж ещё и async-refresh'ит
    // участников — несколько pump'ов, чтобы дерево и счётчик устоялись.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  }

  /// Badge.label живёт в проперти, а не в subtree — ищем по самому виджету.
  Finder badgeWithCount(String count) => find.byWidgetPredicate(
        (w) => w is Badge && w.label is Text && (w.label! as Text).data == count,
      );

  // AC:RL-knock-requests/1 — группа: админ видит бейдж.
  testWidgets('группа: админ видит бейдж с числом заявок', (tester) async {
    await pump(tester, buildRoom(knocking: 2, ownPowerLevel: 100));
    expect(badgeWithCount('2'), findsOneWidget);
    await teardownTree(tester);
  });

  // AC:RL-knock-requests/2 — рядовой участник бейдж не видит.
  testWidgets('группа: без права модератора бейдж не рисуется', (tester) async {
    await pump(tester, buildRoom(knocking: 2, ownPowerLevel: 0));
    expect(badgeWithCount('2'), findsNothing);
    await teardownTree(tester);
  });

  // AC:RL-knock-requests/3 — 0 заявок → нет бейджа.
  testWidgets('группа: у админа без заявок бейджа нет', (tester) async {
    await pump(tester, buildRoom(knocking: 0, ownPowerLevel: 100));
    expect(badgeWithCount('0'), findsNothing);
    await teardownTree(tester);
  });

  // AC:RL-knock-requests/1 — компания (space): владелец видит бейдж.
  testWidgets('компания: владелец видит бейдж', (tester) async {
    await pump(
      tester,
      buildRoom(knocking: 3, ownPowerLevel: 100, inviteLevel: 0, isSpace: true),
    );
    expect(badgeWithCount('3'), findsOneWidget);
    await teardownTree(tester);
  });

  // AC:RL-knock-requests/2 — КЛЮЧЕВОЙ анти-утечка кейс: у компании
  // (space) invite:0 → сломанный гейт room.canInvite показал бы бейдж рядовому
  // участнику. Гейт по moderatorPowerLevel этого не допускает.
  testWidgets('компания: рядовой участник (invite:0) бейдж НЕ видит',
      (tester) async {
    await pump(
      tester,
      buildRoom(knocking: 3, ownPowerLevel: 0, inviteLevel: 0, isSpace: true),
    );
    expect(badgeWithCount('3'), findsNothing);
    await teardownTree(tester);
  });
}
