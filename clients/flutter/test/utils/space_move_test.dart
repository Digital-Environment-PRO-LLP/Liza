// Страж LABA-2539: «Переместить в другое пространство» переносит ЧАТ, а не
// пространство в само себя. До фикса `space_view.dart` слал
// `newSpace.setSpaceChild(newSpace.id)` — добавлял новое пространство ребёнком
// самому себе, после чего снимал чат со старого родителя: чат пропадал из
// иерархии вовсе, а self-ребро ломало серверное определение root-space
// (`single_space_guard` считает главным space БЕЗ входящего m.space.child).
//
// ledger:RL-b2c-chat-outside-space

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/space_move.dart';

import 'test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late FakeMatrixApi api;

  const oldSpaceId = '!old-space:example.invalid';
  const newSpaceId = '!new-space:example.invalid';
  const childIds = <String, String>{
    'группа': '!group:example.invalid',
    'канал': '!channel:example.invalid',
    'суб-пространство': '!subspace:example.invalid',
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FakeMatrixApi();
    // FakeMatrixApi отвечает M_UNRECOGNIZED на незарегистрированный путь, а
    // `setSpaceChild`/`removeSpaceChild` бросают на ошибке — без этих хендлеров
    // тест падал бы раньше, чем дошёл до проверки state_key.
    api.api['PUT'] ??= {};
    final allRooms = [...childIds.values, oldSpaceId, newSpaceId];
    for (final a in allRooms) {
      for (final b in allRooms) {
        // SDK пишет ОБЕ стороны связи: m.space.child у родителя и
        // m.space.parent у ребёнка (`Room.setSpaceChild`, matrix 4.1) — значит
        // баг `setSpaceChild(newSpace.id)` вешал пространству ещё и
        // родителя-самого-себя.
        for (final type in const ['m.space.child', 'm.space.parent']) {
          final path =
              '/client/v3/rooms/${Uri.encodeComponent(a)}'
              '/state/$type/${Uri.encodeComponent(b)}';
          api.api['PUT']![path] = (_) => {'event_id': '\$space_link'};
        }
      }
    }
    client = await prepareTestClient(loggedIn: true, httpClient: api);
    client.backgroundSync = false;
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  /// Пути `m.space.child`-стейтов, которые реально ушли на сервер, в порядке
  /// вызова. Ключ FakeMatrixApi — полный путь запроса.
  List<String> spaceChildCalls() => FakeMatrixApi.calledEndpoints.keys
      .where((k) => k.contains('/state/m.space.child/'))
      .toList();

  /// Все связи пространств, включая обратную сторону `m.space.parent`, которую
  /// SDK пишет ребёнку.
  List<String> spaceLinkCalls() => FakeMatrixApi.calledEndpoints.keys
      .where(
        (k) =>
            k.contains('/state/m.space.child/') ||
            k.contains('/state/m.space.parent/'),
      )
      .toList();

  /// `setSpaceChild` SDK бросает «Room is not a space!», пока в state нет
  /// `m.room.create` с `type: m.space` — комнаты собираем как настоящие space.
  Room space(String id) {
    final room = Room(id: id, client: client);
    room.setState(
      Event(
        eventId: '\$create-$id',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomCreate,
        content: {'type': 'm.space'},
        room: room,
        stateKey: '',
      ),
    );
    return room;
  }

  // Квантор «∀ переносимых сущностей» из тикета: чат, канал и суб-пространство
  // идут одним и тем же путём — вырожденный «один чат» пропустил бы регресс на
  // соседнем типе.
  for (final child in childIds.entries) {
    test(
      'перенос (${child.key}): state_key — переносимая комната, не пространство',
      () async {
        final from = space(oldSpaceId);
        final to = space(newSpaceId);

        await moveRoomToSpace(from: from, to: to, roomId: child.value);

        final calls = spaceChildCalls();
        final encodedChild = Uri.encodeComponent(child.value);
        final encodedNewSpace = Uri.encodeComponent(newSpaceId);
        final encodedOldSpace = Uri.encodeComponent(oldSpaceId);

        // AC:RL-b2c-chat-outside-space/4 — в НОВОЕ пространство ушёл m.space.child
        // со state_key переносимой комнаты.
        expect(
          calls.any(
            (c) =>
                c.contains('/rooms/$encodedNewSpace/') &&
                c.endsWith('/state/m.space.child/$encodedChild'),
          ),
          isTrue,
          reason:
              'нет setSpaceChild(roomId) в новом пространстве:\n${calls.join('\n')}',
        );

        // AC:RL-b2c-chat-outside-space/4 — из СТАРОГО пространства ребёнок снят.
        expect(
          calls.any(
            (c) =>
                c.contains('/rooms/$encodedOldSpace/') &&
                c.endsWith('/state/m.space.child/$encodedChild'),
          ),
          isTrue,
          reason:
              'нет removeSpaceChild(roomId) в старом пространстве:\n${calls.join('\n')}',
        );

        // AC:RL-b2c-chat-outside-space/4 — RED-PROOF: связи пространства с самим
        // собой нет НИКОГДА, ни прямой, ни обратной (баг слал
        // `setSpaceChild(newSpace.id)`, а SDK дописывал ещё и m.space.parent).
        final links = spaceLinkCalls();
        for (final selfId in const [newSpaceId, oldSpaceId]) {
          final encodedSelf = Uri.encodeComponent(selfId);
          expect(
            links.any(
              (c) =>
                  c.contains('/rooms/$encodedSelf/') &&
                  c.endsWith('/$encodedSelf'),
            ),
            isFalse,
            reason:
                'пространство $selfId связано само с собой:\n${links.join('\n')}',
          );
        }
      },
    );
  }

  test('порядок: сначала добавление в новое, потом снятие со старого', () async {
    final from = space(oldSpaceId);
    final to = space(newSpaceId);
    const roomId = '!group:example.invalid';

    await moveRoomToSpace(from: from, to: to, roomId: roomId);

    final calls = spaceChildCalls();
    final encodedNewSpace = Uri.encodeComponent(newSpaceId);
    final encodedOldSpace = Uri.encodeComponent(oldSpaceId);
    final addIndex = calls.indexWhere(
      (c) => c.contains('/rooms/$encodedNewSpace/'),
    );
    final removeIndex = calls.indexWhere(
      (c) => c.contains('/rooms/$encodedOldSpace/'),
    );

    // AC:RL-b2c-chat-outside-space/4 — обрыв между шагами оставляет чат видимым
    // хотя бы в одном пространстве, а не теряет его.
    expect(addIndex, isNonNegative);
    expect(removeIndex, isNonNegative);
    expect(addIndex, lessThan(removeIndex));
  });
}
