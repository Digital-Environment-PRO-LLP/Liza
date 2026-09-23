// ledger:RL-direct-chat-single-flight
// AC:RL-direct-chat-single-flight/1 AC:RL-direct-chat-single-flight/2
// AC:RL-direct-chat-single-flight/3 AC:RL-direct-chat-single-flight/4
// AC:RL-direct-chat-single-flight/9
// Материализация черновика переехала в воронку — её критерии держатся здесь:
// AC:RL-direct-chat-draft-on-first-send/3 AC:RL-direct-chat-draft-on-first-send/4
// AC:RL-direct-chat-draft-on-first-send/7
//
// Страж single-flight воронки `Client.ensureDirectChat` на ЖИВОМ Client +
// FakeMatrixApi: считаем реальные POST /createRoom, а не вызовы обёртки.
// Инцидент 2026-09-16 (Windows): двойной клик → два параллельных
// startDirectChat → два DM и два приглашения собеседнику.
//
// Red-proof:
//   RP-1 (AC-1): убрать мемо (`map[mxid] ??=`) → createRoom == 2, тест красный.
//   RP-3 (AC-3): не снимать запись по завершению → повтор после ошибки получит
//     закешированную ошибку, createRoom останется 1, тест красный.
//   RP-9 (AC-9): сбрасывать мемо по таймауту view → второй вызов после таймаута
//     создаст вторую комнату, createRoom == 2, тест красный.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/direct_chat_ensure.dart';
import 'test_client.dart';

const _bob = '@bob:example.invalid';
const _carol = '@carol:example.invalid';

void main() {
  late Client client;
  late FakeMatrixApi api;
  late int createRoomCalls;
  late Duration savedTimeout;
  // Все клиенты теста: FakeMatrixApi один на всех, hook не знает, кто звонит.
  late List<Client> clients;

  /// Подменяет createRoom: считает вызовы и (опционально) сразу кладёт комнату в
  /// client.rooms — FakeMatrixApi не проталкивает созданную комнату через sync,
  /// без этого startDirectChat уходит в waitForRoomInSync (см.
  /// stories_extension_test.dart).
  void hookCreateRoom({bool injectRoom = true, bool fail = false}) {
    var n = 0;
    api.api['POST']!['/client/v3/createRoom'] = (_) {
      createRoomCalls++;
      if (fail) return {'errcode': 'M_UNKNOWN', 'error': 'boom'};
      final roomId = '!created${n++}:example.invalid';
      if (injectRoom) {
        for (final c in clients) {
          c.rooms = [...c.rooms, Room(id: roomId, client: c)];
        }
      }
      return {'room_id': roomId};
    };
  }

  /// Доносит комнату «через sync» до зависшего waitForRoomInSync.
  Future<void> deliverSync(String roomId) async {
    client.rooms = [...client.rooms, Room(id: roomId, client: client)];
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'b-$roomId',
        rooms: RoomsUpdate(join: {roomId: JoinedRoomUpdate()}),
      ),
    );
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
  }

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    FakeMatrixApi.client = client;
    api = (client.httpClient as dynamic).inner as FakeMatrixApi;
    createRoomCalls = 0;
    clients = [client];
    savedTimeout = ensureDirectChatTimeout;
    hookCreateRoom();
  });

  tearDown(() async {
    ensureDirectChatTimeout = savedTimeout;
    await client.dispose(closeDatabase: true);
  });

  group('AC-1: N параллельных вызовов → ровно один createRoom', () {
    test('a) второй вызов ДО ответа createRoom', () async {
      final f1 = client.ensureDirectChat(_bob);
      final f2 = client.ensureDirectChat(_bob);
      final ids = await Future.wait([f1, f2]);
      expect(ids[0], ids[1]);
      expect(createRoomCalls, 1);
    });

    test('a) три вызова подряд', () async {
      final ids = await Future.wait([
        client.ensureDirectChat(_bob),
        client.ensureDirectChat(_bob),
        client.ensureDirectChat(_bob),
      ]);
      expect(ids.toSet().length, 1);
      expect(createRoomCalls, 1);
    });

    test('b) второй вызов ПОСЛЕ createRoom, но ДО прихода sync', () async {
      // Комната не инжектится → первый вызов висит в waitForRoomInSync.
      hookCreateRoom(injectRoom: false);
      final f1 = client.ensureDirectChat(_bob);
      // Даём createRoom отработать: первый вызов уже ждёт sync.
      while (createRoomCalls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final f2 = client.ensureDirectChat(_bob);
      await deliverSync('!created0:example.invalid');
      final ids = await Future.wait([f1, f2]);
      expect(ids[0], '!created0:example.invalid');
      expect(ids[1], ids[0]);
      expect(createRoomCalls, 1);
    });
  });

  test('AC-2: после успеха повтор НЕ создаёт вторую комнату', () async {
    final first = await client.ensureDirectChat(_bob);
    // m.direct записан → SDK-ветка «существующий join-DM».
    expect(client.getDirectChatFromUserId(_bob), first);
    final second = await client.ensureDirectChat(_bob);
    expect(second, first);
    expect(createRoomCalls, 1);
  });

  test('AC-3: ошибка createRoom → все ожидающие падают, запись сброшена, '
      'повтор пробует снова', () async {
    hookCreateRoom(fail: true);
    final f1 = client.ensureDirectChat(_bob);
    final f2 = client.ensureDirectChat(_bob);
    await expectLater(f1, throwsA(isA<MatrixException>()));
    await expectLater(f2, throwsA(isA<MatrixException>()));
    expect(createRoomCalls, 1);

    hookCreateRoom();
    final id = await client.ensureDirectChat(_bob);
    expect(id, startsWith('!created'));
    expect(createRoomCalls, 2);
  });

  group('AC-4: ключ — пара (Client, mxid)', () {
    test('один Client × два mxid → две комнаты', () async {
      final ids = await Future.wait([
        client.ensureDirectChat(_bob),
        client.ensureDirectChat(_carol),
      ]);
      expect(ids[0], isNot(ids[1]));
      expect(createRoomCalls, 2);
    });

    test('два Client × один mxid → по комнате на каждого', () async {
      // Тот же FakeMatrixApi (и hook со счётчиком) — иначе у второго клиента
      // дефолтный createRoom без инжекта комнаты и вечный waitForRoomInSync.
      final other = await prepareTestClient(
        loggedIn: true,
        clientName: 'Liza Widget Tests 2',
        homeserver: Uri.parse('https://second.notexisting'),
        httpClient: api,
      );
      clients.add(other);
      try {
        final ids = await Future.wait([
          client.ensureDirectChat(_bob),
          other.ensureDirectChat(_bob),
        ]);
        expect(ids[0], isNot(ids[1]));
        expect(createRoomCalls, 2);
      } finally {
        await other.dispose(closeDatabase: true);
      }
    });
  });

  test(
    'AC-9: таймаут view НЕ сбрасывает мемо — второй вызов не плодит комнату',
    () async {
      ensureDirectChatTimeout = const Duration(milliseconds: 50);
      hookCreateRoom(injectRoom: false); // sync молчит → underlying висит
      await expectLater(
        client.ensureDirectChat(_bob),
        throwsA(isA<TimeoutException>()),
      );
      // Underlying ещё в полёте: повторный клик ждёт ТУ ЖЕ операцию.
      final f2 = client.ensureDirectChat(_bob);
      await expectLater(f2, throwsA(isA<TimeoutException>()));
      expect(createRoomCalls, 1);

      // Sync ожил → операция дозавершается, m.direct записан, дальше — SDK-ветка.
      await deliverSync('!created0:example.invalid');
      ensureDirectChatTimeout = savedTimeout;
      final id = await client.ensureDirectChat(_bob);
      expect(id, '!created0:example.invalid');
      expect(createRoomCalls, 1);
    },
  );
}
