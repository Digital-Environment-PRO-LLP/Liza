import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/miniapp_room.dart';
import 'test_client.dart';

// Помимо «+»-меню, isBotFatherRoom управляет видимостью меню-кнопки композера
// (chat_input_row) — ledger:RL-composer-botfather-menu-button.
void main() {
  group('isBotFatherRoom — «+»-меню и меню-кнопка композера [ledger:RL-composer-botfather-menu-button]', () {
    test('DM с @bot_father → true (в т.ч. cross-HS домен)', () async {
      final client = await prepareTestClient(loggedIn: true);
      client.rooms.clear();

      const botfatherDm = '!bf:example.invalid';
      const crossHsDm = '!bf2:example.invalid';
      const userDm = '!bob:example.invalid';
      const group = '!group:example.invalid';

      client.rooms.addAll([
        Room(id: botfatherDm, client: client),
        Room(id: crossHsDm, client: client),
        Room(id: userDm, client: client),
        Room(id: group, client: client),
      ]);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          // Бот на «своём» сервере.
          '@bot_father:example.invalid': [botfatherDm],
          // Тот же localpart на другом HS (компания/dev) — тоже BotFather.
          '@bot_father:nadezhda.liza.ru': [crossHsDm],
          '@bob:example.invalid': [userDm],
        },
      );

      expect(isBotFatherRoom(client.getRoomById(botfatherDm)!), isTrue);
      expect(isBotFatherRoom(client.getRoomById(crossHsDm)!), isTrue,
          reason: 'сверяем только localpart, домен любой');
      expect(isBotFatherRoom(client.getRoomById(userDm)!), isFalse,
          reason: 'обычный собеседник — не BotFather');
      expect(isBotFatherRoom(client.getRoomById(group)!), isFalse,
          reason: 'групповая комната (нет directChatMatrixID) — не BotFather');

      await client.dispose(closeDatabase: true);
    });

    test('DM с @botfather (новый, без подчёркивания) → true', () async {
      final client = await prepareTestClient(loggedIn: true);
      client.rooms.clear();

      const botfatherDm = '!bf3:example.invalid';
      client.rooms.add(Room(id: botfatherDm, client: client));
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@botfather:bots.liza.ru': [botfatherDm],
        },
      );

      expect(isBotFatherRoom(client.getRoomById(botfatherDm)!), isTrue);

      await client.dispose(closeDatabase: true);
    });

    test('похожий, но не тот MXID (@bot_father_bot) → false', () async {
      final client = await prepareTestClient(loggedIn: true);
      client.rooms.clear();
      const dm = '!x:example.invalid';
      client.rooms.add(Room(id: dm, client: client));
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bot_father_bot:example.invalid': [dm],
        },
      );

      expect(isBotFatherRoom(client.getRoomById(dm)!), isFalse);

      await client.dispose(closeDatabase: true);
    });

    // Группа «Группа с BotFather» (directChatMatrixID == null): детектим по
    // участнику-боту. Именно этот путь показывает меню-кнопку в композере.
    test('ГРУППА с участником @botfather → true; без него → false', () async {
      final client = await prepareTestClient(loggedIn: true);
      client.rooms.clear();
      final selfId = client.userID!;

      Event memberEv(Room room, String mxid) => Event(
            eventId: '\$m-$mxid',
            senderId: mxid,
            originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
            type: EventTypes.RoomMember,
            stateKey: mxid,
            content: const {'membership': 'join'},
            room: room,
          );

      final bfGroup = Room(id: '!g1:example.invalid', client: client);
      bfGroup.setState(memberEv(bfGroup, selfId));
      bfGroup.setState(memberEv(bfGroup, '@botfather:bots.liza.ru'));

      final plainGroup = Room(id: '!g2:example.invalid', client: client);
      plainGroup.setState(memberEv(plainGroup, selfId));
      plainGroup.setState(memberEv(plainGroup, '@alice:example.invalid'));

      client.rooms.addAll([bfGroup, plainGroup]);

      expect(isBotFatherRoom(bfGroup), isTrue,
          reason: 'групповой чат с ботом-участником — BotFather');
      expect(isBotFatherRoom(plainGroup), isFalse,
          reason: 'группа без бота — не BotFather');

      await client.dispose(closeDatabase: true);
    });
  });
}
