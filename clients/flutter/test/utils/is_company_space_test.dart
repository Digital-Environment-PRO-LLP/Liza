// ignore_for_file: depend_on_referenced_packages

// Регресс: изначальная реализация isCompanyRoom считала room.spaceParents —
// SDK прямо предупреждает, что это ненадёжно (обратная связь ребёнок→родитель
// не гарантирована), и у комнат, привязанных к компании СЕРВЕРОМ
// (single_space_guard пишет только m.space.child), m.space.parent нет вовсе.
// Итог: суб-пространство получало isCompanyRoom == true и показывало «Админ
// компании» вместо «Админ пространства». Классификация — обратным обходом по
// spaceChildren; наличие m.space.parent у ребёнка (setSpaceChild SDK 4.1 и
// подпространства LABA-2532 его пишут) ничего не меняет.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

import 'test_client.dart';

void main() {
  group('isCompanySpace', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    void createEvent(Room room) {
      room.setState(
        Event(
          eventId: '\$create',
          senderId: '@creator:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: EventTypes.RoomCreate,
          content: {'type': 'm.space'},
          room: room,
          stateKey: '',
        ),
      );
    }

    void setSpaceChild(Room parent, String childRoomId) {
      parent.setState(
        Event(
          eventId: '\$child',
          senderId: '@creator:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: EventTypes.SpaceChild,
          content: {
            'via': ['example.invalid'],
          },
          room: parent,
          stateKey: childRoomId,
        ),
      );
    }

    test('обычная комната (не space) — не компания', () {
      final room = Room(id: '!room:example.invalid', client: client);
      expect(isCompanySpace(space: room, allRooms: [room]), isFalse);
    });

    test('пространство без родителей и без ссылающихся space — компания', () {
      final company = Room(id: '!company:example.invalid', client: client);
      createEvent(company);
      expect(isCompanySpace(space: company, allRooms: [company]), isTrue);
    });

    test('суб-пространство — НЕ компания, даже если spaceParents пуст '
        '(комнаты, привязанные сервером, m.space.parent не имеют)', () {
      final company = Room(id: '!company:example.invalid', client: client);
      final sub = Room(id: '!sub:example.invalid', client: client);
      createEvent(company);
      createEvent(sub);
      setSpaceChild(company, sub.id);

      // Регресс-условие: у суб-пространства нет m.space.parent — так выглядит
      // комната, вложенная в компанию сервером; классификация не должна
      // зависеть от обратного ребра.
      expect(sub.spaceParents, isEmpty);

      expect(isCompanySpace(space: sub, allRooms: [company, sub]), isFalse);
      expect(isCompanySpace(space: company, allRooms: [company, sub]), isTrue);
    });

    test('пространство не ссылается само на себя как на ребёнка', () {
      final company = Room(id: '!company:example.invalid', client: client);
      createEvent(company);
      setSpaceChild(company, company.id);
      expect(
        isCompanySpace(space: company, allRooms: [company]),
        isTrue,
        reason: 'r.id != space.id должен отсечь самоссылку',
      );
    });
  });
}
