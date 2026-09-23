import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/miniapp_room.dart';
import 'test_client.dart';

// Страж реестра регрессии: ledger:RL-deleted-bot-account (см. tests/registry/).
// Покрывает isDeletedBotDm — предикат определяет DM с удалённым ботом
// (peer из домена bots.liza.ru + membership==leave). LABA-2242.
//
// AC-1: DM с ботом (bots.liza.ru), где peer вышел → isDeletedBotDm = true.
// AC-4: DM с человеком (не bots.liza.ru), peer вышел → isDeletedBotDm = false.
// AC-5: DM с ботом (bots.liza.ru), peer ещё в комнате → isDeletedBotDm = false.

/// Конструирует member-state-event с заданным membership.
Event _memberEvent(Room room, String mxid, String membership) => Event(
      eventId: '\$m-$mxid',
      senderId: mxid,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      type: EventTypes.RoomMember,
      stateKey: mxid,
      content: {'membership': membership},
      room: room,
    );

void main() {
  group(
    'isDeletedBotDm — DM с удалённым ботом [ledger:RL-deleted-bot-account]',
    () {
      // AC-1: бот на bots.liza.ru вышел из комнаты → true.
      test(
        'AC:RL-deleted-bot-account/1 — DM с ботом bots.liza.ru, peer leave → true',
        () async {
          final client = await prepareTestClient(loggedIn: true);
          client.rooms.clear();
          final selfId = client.userID!;
          const botMxid = '@mybot:bots.liza.ru';
          const roomId = '!bot-dm:example.invalid';

          final room = Room(id: roomId, client: client);
          room.setState(_memberEvent(room, selfId, 'join'));
          room.setState(_memberEvent(room, botMxid, 'leave'));
          client.rooms.add(room);
          client.accountData['m.direct'] = BasicEvent(
            type: 'm.direct',
            content: {
              botMxid: [roomId],
            },
          );

          expect(
            isDeletedBotDm(client.getRoomById(roomId)!),
            isTrue,
            reason: 'бот на bots.liza.ru с membership=leave → удалённый аккаунт',
          );

          await client.dispose(closeDatabase: true);
        },
      );

      // AC-4 (изоляция): peer — человек (не bots.liza.ru), даже если вышел → false.
      test(
        'AC:RL-deleted-bot-account/4 — DM с человеком (не bots.liza.ru), peer leave → false',
        () async {
          final client = await prepareTestClient(loggedIn: true);
          client.rooms.clear();
          final selfId = client.userID!;
          const humanMxid = '@alice:example.invalid';
          const roomId = '!human-dm:example.invalid';

          final room = Room(id: roomId, client: client);
          room.setState(_memberEvent(room, selfId, 'join'));
          room.setState(_memberEvent(room, humanMxid, 'leave'));
          client.rooms.add(room);
          client.accountData['m.direct'] = BasicEvent(
            type: 'm.direct',
            content: {
              humanMxid: [roomId],
            },
          );

          expect(
            isDeletedBotDm(client.getRoomById(roomId)!),
            isFalse,
            reason: 'обычный человек, вышедший из DM — не «Удалённый аккаунт»',
          );

          await client.dispose(closeDatabase: true);
        },
      );

      // AC-5 (изоляция): бот на bots.liza.ru, но ещё join → false.
      test(
        'AC:RL-deleted-bot-account/5 — DM с ботом bots.liza.ru, peer join → false',
        () async {
          final client = await prepareTestClient(loggedIn: true);
          client.rooms.clear();
          final selfId = client.userID!;
          const botMxid = '@livebot:bots.liza.ru';
          const roomId = '!live-bot-dm:example.invalid';

          final room = Room(id: roomId, client: client);
          room.setState(_memberEvent(room, selfId, 'join'));
          room.setState(_memberEvent(room, botMxid, 'join'));
          client.rooms.add(room);
          client.accountData['m.direct'] = BasicEvent(
            type: 'm.direct',
            content: {
              botMxid: [roomId],
            },
          );

          expect(
            isDeletedBotDm(client.getRoomById(roomId)!),
            isFalse,
            reason: 'живой бот (membership=join) — не «Удалённый аккаунт»',
          );

          await client.dispose(closeDatabase: true);
        },
      );

      // Дополнительный: групповая комната (не DM) → false.
      test(
        'группа с ботом (не DM, нет directChatMatrixID) → false',
        () async {
          final client = await prepareTestClient(loggedIn: true);
          client.rooms.clear();
          final selfId = client.userID!;
          const botMxid = '@mybot:bots.liza.ru';
          const roomId = '!group:example.invalid';

          final room = Room(id: roomId, client: client);
          room.setState(_memberEvent(room, selfId, 'join'));
          room.setState(_memberEvent(room, botMxid, 'leave'));
          // Не добавляем m.direct → directChatMatrixID == null
          client.rooms.add(room);

          expect(
            isDeletedBotDm(client.getRoomById(roomId)!),
            isFalse,
            reason: 'групповая комната (без directChatMatrixID) — не DM',
          );

          await client.dispose(closeDatabase: true);
        },
      );

      // Дополнительный: бот на bots.liza.ru, kicked (membership=ban) → false
      // (баним человека, а не «удаляем» — поведение invite-kick-ban в стандарте).
      test(
        'DM с ботом bots.liza.ru, peer membership=ban → false (не удаление)',
        () async {
          final client = await prepareTestClient(loggedIn: true);
          client.rooms.clear();
          final selfId = client.userID!;
          const botMxid = '@badbot:bots.liza.ru';
          const roomId = '!banned-bot-dm:example.invalid';

          final room = Room(id: roomId, client: client);
          room.setState(_memberEvent(room, selfId, 'join'));
          room.setState(_memberEvent(room, botMxid, 'ban'));
          client.rooms.add(room);
          client.accountData['m.direct'] = BasicEvent(
            type: 'm.direct',
            content: {
              botMxid: [roomId],
            },
          );

          // ban != leave → isDeletedBotDm false (это ban, не деактивация)
          expect(
            isDeletedBotDm(client.getRoomById(roomId)!),
            isFalse,
            reason: 'banned (не leave) — isDeletedBotDm false',
          );

          await client.dispose(closeDatabase: true);
        },
      );
    },
  );
}
