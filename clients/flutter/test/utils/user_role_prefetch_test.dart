// Юнит-тест для collectDmPartnersForPrefetch из widgets/matrix.dart.
//
// Проверяем, что при префетче ролей при заходе в приложение мы берём ТОЛЬКО
// DM-партнёров (бейдж роли виден лишь в direct-чатах) плюс собственный
// matrix-ID (нужен для IfDeveloper и подобных role-gated виджетов).
// Групповые чаты и спейсы не должны попадать в выборку.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/widgets/matrix.dart';

import 'test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('collectDmPartnersForPrefetch', () {
    test(
      'возвращает только DM-партнёров и собственный matrix-ID',
      () async {
        final client = await prepareTestClient(loggedIn: true);
        // prepareTestClient логинит как @alice:example.invalid.
        final userId = client.userID!;

        // Очищаем предзаготовленные комнаты от FakeMatrixApi /sync,
        // чтобы строить состояние строго под тест.
        client.rooms.clear();

        const dmRoomId = '!dm:example.invalid';
        const groupRoomId = '!group:example.invalid';
        const spaceRoomId = '!space:example.invalid';
        const dmPartner = '@bob:example.invalid';
        const groupMate = '@carol:example.invalid';

        client.rooms.addAll([
          Room(id: dmRoomId, client: client),
          Room(id: groupRoomId, client: client),
          Room(id: spaceRoomId, client: client),
        ]);

        // m.direct account_data маркирует только dmRoomId как direct-чат
        // c @bob. Group и space остаются обычными комнатами.
        client.accountData['m.direct'] = BasicEvent(
          type: 'm.direct',
          content: {
            dmPartner: [dmRoomId],
            // Партнёр без живой комнаты не должен вкатываться:
            // directChatMatrixID учитывает только id-комнат из rooms.
            '@orphan:example.invalid': ['!missing:example.invalid'],
            // groupMate отсутствует — групповая комната не direct.
          },
        );

        final result = collectDmPartnersForPrefetch(client);

        expect(result, contains(dmPartner));
        expect(result, contains(userId));
        expect(
          result,
          isNot(contains(groupMate)),
          reason: 'участники групповых комнат не должны префетчиться',
        );
        expect(
          result,
          isNot(contains('@orphan:example.invalid')),
          reason: 'DM-партнёр без существующей комнаты не должен попадать',
        );
        expect(result.length, 2,
            reason: 'ожидаем ровно dmPartner и userID, без лишнего шума');

        await client.dispose(closeDatabase: true);
      },
    );

    test(
      'без direct-чатов возвращает только собственный matrix-ID',
      () async {
        final client = await prepareTestClient(loggedIn: true);
        final userId = client.userID!;

        client.rooms.clear();
        client.rooms.add(Room(id: '!only-group:example.invalid', client: client));

        // m.direct отсутствует совсем.
        client.accountData.remove('m.direct');

        final result = collectDmPartnersForPrefetch(client);

        expect(result, {userId});

        await client.dispose(closeDatabase: true);
      },
    );
  });
}
