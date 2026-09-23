// ignore_for_file: depend_on_referenced_packages
//
// Страж RL-unread-rooms-badge-visible-only: бейдж непрочитанных на базе виджета
// UnreadRoomsBadge (кнопка «назад» в чате + оба nav-rail-бейджа) считает ТОЛЬКО
// видимые непрочитанные комнаты — по тому же инварианту, что иконка приложения и
// список чатов (`countsTowardAppBadge = !isHiddenChat && isUnreadOrInvited`).
// Скрытые (stories / topology-hidden обсуждение канала) непрочитанные комнаты не
// увеличивают счётчик: их нельзя открыть и «прочитать», поэтому они не должны
// оставлять неснимаемый фантомный бейдж. Рендерит РЕАЛЬНЫЙ прод-виджет
// UnreadRoomsBadge через Matrix.of(context).
//
// Баг Саши (2026-08-13): в списке чатов и на иконке приложения непрочитанных нет,
// но на кнопке «назад» висела неснимаемая «2» от скрытой непрочитанной комнаты.
// ledger:RL-unread-rooms-badge-visible-only

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/utils/chat_topology.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;
import 'package:liza/widgets/unread_rooms_badge.dart';

import '../utils/test_client.dart';

// UnreadRoomsBadge читает только Matrix.of(context).client.rooms. Полный
// Matrix-виджет (initMatrix/push/DB) в юнит-тесте неоправданно тяжёл — подменяем
// единственный геттер, который читает бейдж.
class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

Widget _wrap(Widget child, liza_matrix.MatrixState state) => MaterialApp(
      home: Provider<liza_matrix.MatrixState>.value(
        value: state,
        child: Scaffold(body: child),
      ),
    );

// FakeMatrixApi при логине наполняет client.rooms своими дефолтными комнатами
// (домен `:example.com`). Изолируем счёт только на наши тест-комнаты
// (`:example.invalid`) — call-site filter и так произвольный, топология
// (countsTowardAppBadge) проверяется поверх него.
bool _mine(Room r) => r.id.endsWith(':example.invalid');

/// Число в бейдже виджета (badgeContent — Text с числом). 0 = непрочитанных нет.
int _badgeCount(WidgetTester tester) {
  final textWidget = tester.widget<Text>(
    find.descendant(
      of: find.byType(UnreadRoomsBadge),
      matching: find.byType(Text),
    ),
  );
  return int.parse(textWidget.data!);
}

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    // Логин запускает фоновый sync-loop (FakeMatrixApi отвечает бесконечно) →
    // комнаты наполняем вручную через handleSync, фоновый sync не нужен.
    client.backgroundSync = false;
    await client.abortSync();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  // handleSync/DB — реальные async-операции (sqflite-ffi, таймеры). В теле
  // testWidgets царит FakeAsync, который их не продвигает → без runAsync
  // handleSync висит. runAsync прогоняет их в реальном времени.
  Future<void> joinUnreadRoom(
    WidgetTester tester,
    String roomId, {
    Map<String, dynamic> createContent = const {},
    Map<String, dynamic>? topologyContent,
    int notificationCount = 2,
  }) =>
      tester.runAsync(() => client.handleSync(
            SyncUpdate(
              nextBatch: 'b-$roomId',
              rooms: RoomsUpdate(
                join: {
                  roomId: JoinedRoomUpdate(
                    unreadNotifications: UnreadNotificationCounts(
                      notificationCount: notificationCount,
                      highlightCount: 0,
                    ),
                    state: [
                      MatrixEvent(
                        type: EventTypes.RoomCreate,
                        eventId: '\$create-$roomId',
                        senderId: '@alice:example.invalid',
                        originServerTs: DateTime.now(),
                        content: createContent,
                        stateKey: '',
                      ),
                      if (topologyContent != null)
                        MatrixEvent(
                          type: 'com.liza.chat.topology',
                          eventId: '\$topology-$roomId',
                          senderId: '@alice:example.invalid',
                          originServerTs: DateTime.now(),
                          content: topologyContent,
                          stateKey: '',
                        ),
                    ],
                  ),
                },
              ),
            ),
          ));

  Future<void> inviteRoom(
    WidgetTester tester,
    String roomId, {
    Map<String, dynamic> createContent = const {},
  }) =>
      tester.runAsync(() => client.handleSync(
            SyncUpdate(
              nextBatch: 'b-inv-$roomId',
              rooms: RoomsUpdate(
                invite: {
                  roomId: InvitedRoomUpdate(
                    inviteState: [
                      StrippedStateEvent(
                        type: EventTypes.RoomCreate,
                        senderId: '@alice:example.invalid',
                        content: createContent,
                        stateKey: '',
                      ),
                    ],
                  ),
                },
              ),
            ),
          ));

  // AC-1: скрытая непрочитанная stories-комната НЕ считается.
  // AC:RL-unread-rooms-badge-visible-only/1
  testWidgets('скрытая stories-комната с непрочитанным → бейдж 0', (
    tester,
  ) async {
    await joinUnreadRoom(
      tester,
      '!stories:example.invalid',
      createContent: {'com.liza.chat.type': 'stories'},
      notificationCount: 3,
    );
    await tester.pumpWidget(
      _wrap(UnreadRoomsBadge(filter: _mine), _TestMatrixState(client)),
    );
    await tester.pump();
    expect(_badgeCount(tester), 0, reason: 'stories скрыт → не в бейдж');
  });

  // AC-2: скрытое обсуждение канала (topology hidden, partial-путь sync) НЕ
  // считается. Смежно с RL-discussion-hidden-on-sync (топология переживает sync).
  // AC:RL-unread-rooms-badge-visible-only/2
  testWidgets('скрытое обсуждение канала с непрочитанным → бейдж 0', (
    tester,
  ) async {
    await joinUnreadRoom(
      tester,
      '!discussion:example.invalid',
      createContent: {'com.liza.chat.type': 'channel_discussion'},
      topologyContent: const {'hidden': true},
    );
    expect(
      client.getRoomById('!discussion:example.invalid')!.isHiddenChat,
      isTrue,
      reason: 'предусловие: обсуждение скрыто после sync',
    );
    await tester.pumpWidget(
      _wrap(UnreadRoomsBadge(filter: _mine), _TestMatrixState(client)),
    );
    await tester.pump();
    expect(_badgeCount(tester), 0, reason: 'скрытое обсуждение → не в бейдж');
  });

  // AC-3: обычная непрочитанная видимая комната считается (защита от ложного
  // сужения — фикс не должен обнулить легитимный счёт).
  // AC:RL-unread-rooms-badge-visible-only/3
  testWidgets('обычная непрочитанная комната → бейдж считается', (tester) async {
    await joinUnreadRoom(tester, '!normal:example.invalid');
    await tester.pumpWidget(
      _wrap(UnreadRoomsBadge(filter: _mine), _TestMatrixState(client)),
    );
    await tester.pump();
    expect(_badgeCount(tester), 1, reason: 'видимая непрочитанная считается');
  });

  // AC-4: invite в СКРЫТУЮ комнату не считается; invite в ОБЫЧНУЮ — считается.
  // AC:RL-unread-rooms-badge-visible-only/4
  testWidgets('invite: скрытая не считается, обычная считается', (tester) async {
    await inviteRoom(
      tester,
      '!inv-hidden:example.invalid',
      createContent: {'com.liza.chat.type': 'stories'},
    );
    await inviteRoom(tester, '!inv-normal:example.invalid');
    await tester.pumpWidget(
      _wrap(UnreadRoomsBadge(filter: _mine), _TestMatrixState(client)),
    );
    await tester.pump();
    expect(
      _badgeCount(tester),
      1,
      reason: 'обычный invite в счётчик, invite в скрытую — нет',
    );
  });

  // AC-5: персонально раскрытая (isRevealedByMe) ранее-скрытая непрочитанная —
  // снова считается (раскрытие сильнее общей скрытости).
  // AC:RL-unread-rooms-badge-visible-only/5
  testWidgets('раскрытая ранее-скрытая непрочитанная → снова считается', (
    tester,
  ) async {
    const roomId = '!revealed:example.invalid';
    await joinUnreadRoom(
      tester,
      roomId,
      createContent: {'com.liza.chat.type': 'stories'},
    );
    final room = client.getRoomById(roomId)!;
    room.roomAccountData[chatRevealedAccountDataType] = BasicEvent(
      type: chatRevealedAccountDataType,
      content: const {'revealed': true},
    );
    expect(room.isHiddenChat, isFalse, reason: 'раскрытая ≠ скрытая');
    await tester.pumpWidget(
      _wrap(UnreadRoomsBadge(filter: _mine), _TestMatrixState(client)),
    );
    await tester.pump();
    expect(_badgeCount(tester), 1, reason: 'раскрытая непрочитанная считается');
  });

  // AC-6: ∀ трёх filter-call-site итог = filter && countsTowardAppBadge. Один
  // мультикейсный ассерт: filter (r)=>true (nav-rail «Чаты»),
  // (r)=>r.id!=X (кнопка «назад»), (r)=>ids.contains (nav-rail пространства).
  // AC:RL-unread-rooms-badge-visible-only/6
  testWidgets('фильтр call-site комбинируется с топологией корректно', (
    tester,
  ) async {
    await joinUnreadRoom(tester, '!normal:example.invalid'); // видимая → 1
    await joinUnreadRoom(
      tester,
      '!stories:example.invalid',
      createContent: {'com.liza.chat.type': 'stories'},
    ); // скрытая → 0
    await joinUnreadRoom(tester, '!other:example.invalid'); // видимая → 1
    final state = _TestMatrixState(client);

    // filter (r)=>true (nav-rail «Чаты»): считает обе видимые, скрытую нет.
    await tester.pumpWidget(_wrap(UnreadRoomsBadge(filter: _mine), state));
    await tester.pump();
    expect(_badgeCount(tester), 2, reason: 'filter=true → 2 видимые');

    // filter (r)=>r.id!=normal (кнопка «назад» из !normal): исключает текущую,
    // остаётся 1 видимая (!other), скрытая по-прежнему не в счёт.
    await tester.pumpWidget(
      _wrap(
        UnreadRoomsBadge(filter: (r) => _mine(r) && r.id != '!normal:example.invalid'),
        state,
      ),
    );
    await tester.pump();
    expect(_badgeCount(tester), 1, reason: 'кнопка «назад» из !normal → 1');

    // filter (r)=>ids.contains (nav-rail пространства): только !other в space.
    await tester.pumpWidget(
      _wrap(
        UnreadRoomsBadge(
          filter: (r) => {'!other:example.invalid'}.contains(r.id),
        ),
        state,
      ),
    );
    await tester.pump();
    expect(_badgeCount(tester), 1, reason: 'space-скоуп {!other} → 1');
  });

  // AC-7: реактивность — при обновлении по onSync счётчик пересчитывается без
  // «перезахода» (жалоба Саши: «выходил-заходил не помогало»). Воспроизводим
  // проводку call-site: UnreadRoomsBadge под StreamBuilder(onSync) как в
  // chat_view.dart:298.
  // AC:RL-unread-rooms-badge-visible-only/7
  testWidgets('реактивность: новый непрочитанный доезжает по onSync', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        StreamBuilder<Object>(
          stream: client.onSync.stream.where((s) => s.hasRoomUpdate),
          builder: (context, _) => UnreadRoomsBadge(filter: _mine),
        ),
        _TestMatrixState(client),
      ),
    );
    await tester.pump();
    expect(_badgeCount(tester), 0, reason: 'старт: непрочитанных нет');

    await joinUnreadRoom(tester, '!live:example.invalid');
    await tester.pump();
    expect(
      _badgeCount(tester),
      1,
      reason: 'после onSync бейдж пересчитан без перемонтирования',
    );
  });
}
