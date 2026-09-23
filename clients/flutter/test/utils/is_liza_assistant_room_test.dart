import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/miniapp_room.dart';
import 'test_client.dart';

void main() {
  group('isLizaAssistantRoom — закрепление чата ассистента', () {
    const lizaMxid = '@liza:bots.liza.ru';

    test('живой DM на bots → true, мёртвый DM со старой @liza:prod → false',
        () async {
      final client = await prepareTestClient(loggedIn: true);
      client.rooms.clear();

      const botsDm = '!bots:example.invalid';
      const prodDm = '!prod:example.invalid';

      client.rooms.addAll([
        Room(id: botsDm, client: client),
        Room(id: prodDm, client: client),
      ]);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          lizaMxid: [botsDm],
          // Аккаунт деактивирован 2026-07-14, комната осталась у пользователя
          // как «Пустой чат (был Liza)». Тот же localpart, другой домен.
          '@liza:synapse.liza.laba.prodamus.tech': [prodDm],
        },
      );

      expect(isLizaAssistantRoom(client.getRoomById(botsDm)!, lizaMxid), isTrue);
      expect(
        isLizaAssistantRoom(client.getRoomById(prodDm)!, lizaMxid),
        isFalse,
        reason: 'мёртвая @liza на prod не должна перехватывать закрепление',
      );

      await client.dispose(closeDatabase: true);
    });

    test('mini App-чат с @liza (есть m.room.name) → false', () async {
      final client = await prepareTestClient(loggedIn: true);
      client.rooms.clear();

      const miniAppDm = '!app:example.invalid';
      final room = Room(id: miniAppDm, client: client);
      room.setState(
        Event(
          type: EventTypes.RoomName,
          eventId: '\$name',
          senderId: lizaMxid,
          originServerTs: DateTime.now(),
          room: room,
          content: {'name': 'Магазин Prodamus'},
          stateKey: '',
        ),
      );
      client.rooms.add(room);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          lizaMxid: [miniAppDm],
        },
      );

      expect(
        isLizaAssistantRoom(client.getRoomById(miniAppDm)!, lizaMxid),
        isFalse,
        reason: 'mini App-чат имеет своё имя — закрепляем не его',
      );

      await client.dispose(closeDatabase: true);
    });

    test('обычный собеседник и группа → false', () async {
      final client = await prepareTestClient(loggedIn: true);
      client.rooms.clear();

      const userDm = '!bob:example.invalid';
      const group = '!group:example.invalid';

      client.rooms.addAll([
        Room(id: userDm, client: client),
        Room(id: group, client: client),
      ]);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.invalid': [userDm],
        },
      );

      expect(isLizaAssistantRoom(client.getRoomById(userDm)!, lizaMxid), isFalse);
      expect(
        isLizaAssistantRoom(client.getRoomById(group)!, lizaMxid),
        isFalse,
        reason: 'групповая комната — нет directChatMatrixID',
      );

      await client.dispose(closeDatabase: true);
    });
  });
}
