// Страж LABA-2532: подпространство внутри компании создаётся с
// `m.space.parent` в initial_state — иначе серверный `single_space_guard`
// (`_guard.py` `is_root_space_creation`) считает createRoom второй компанией и
// отвечает 403 «Главное пространство уже существует». Прежний путь
// `client.createSpace()` initial_state не передавал вовсе.
//
// Ассерты — по ТЕЛАМ запросов из FakeMatrixApi.calledEndpoints, а не по факту
// вызова: без этого тест зеленел бы и на старом коде.
//
// ledger:RL-subspace-create-with-parent

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/create_subspace.dart';

import 'test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late FakeMatrixApi api;

  // Ответ стаба FakeMatrixApi на POST /createRoom.
  const createdId = '!1234:fakeServer.notExisting';
  const encodedCreated = '!1234%3AfakeServer.notExisting';
  // Домен залогиненного тест-клиента (@test:fakeServer.notExisting).
  late String userDomain;

  String childPutPath(String parentId) =>
      '/client/v3/rooms/${Uri.encodeComponent(parentId)}'
      '/state/m.space.child/$encodedCreated';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FakeMatrixApi();
    api.api['PUT'] ??= {};
    client = await prepareTestClient(loggedIn: true, httpClient: api);
    client.backgroundSync = false;
    userDomain = client.userID!.domain!;
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  /// `createSubspace` не требует, чтобы родитель был space в локальном state
  /// (это проверял бы SDK `setSpaceChild`, который здесь не используется),
  /// но собираем как настоящий — ближе к проду.
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

  Map<String, dynamic> createRoomBody() {
    final bodies = FakeMatrixApi.calledEndpoints['/client/v3/createRoom'];
    expect(bodies, isNotNull, reason: 'createRoom не вызван');
    expect(bodies, hasLength(1), reason: 'createRoom должен быть вызван 1 раз');
    return jsonDecode(bodies!.single as String) as Map<String, dynamic>;
  }

  List<String> spaceLinkCalls() => FakeMatrixApi.calledEndpoints.keys
      .where(
        (k) =>
            k.contains('/state/m.space.child/') ||
            k.contains('/state/m.space.parent/'),
      )
      .toList();

  // AC-8: квантор ∀ по домену родителя — своя компания на домене пользователя
  // и федеративная компания на чужом домене (юзер там админ). via в обоих
  // случаях — домен ПОЛЬЗОВАТЕЛЯ (как в SDK setSpaceChild): его homeserver
  // состоит в родителе, через него родитель и достижим.
  const parents = <String, String>{
    'свой домен': '!company:example.invalid',
    'чужой домен': '!company:other.invalid',
  };

  for (final parent in parents.entries) {
    test(
      'createRoom подпространства (${parent.key}): m.space.parent → родитель',
      () async {
        api.api['PUT']![childPutPath(parent.value)] = (_) => {
          'event_id': '\$child',
        };

        final roomId = await createSubspace(
          parent: space(parent.value),
          name: 'Отдел',
        );

        expect(roomId, createdId);

        final body = createRoomBody();
        // AC:RL-subspace-create-with-parent/1 — это space с админскими
        // правами на state (паритет с Client.createSpace) и ровно одним
        // m.space.parent.
        expect(body['name'], 'Отдел');
        expect(body['visibility'], 'private');
        expect(body['creation_content'], {'type': 'm.space'});
        expect(
          (body['power_level_content_override'] as Map)['events_default'],
          100,
        );
        final initialState = (body['initial_state'] as List)
            .cast<Map<String, dynamic>>();
        final parentEvents = initialState
            .where((e) => e['type'] == 'm.space.parent')
            .toList();
        expect(parentEvents, hasLength(1));

        // AC:RL-subspace-create-with-parent/2 — state_key = id родителя,
        // via = домен пользователя, canonical не кладём (SDK его не читает
        // и не пишет).
        final parentEvent = parentEvents.single;
        expect(parentEvent['state_key'], parent.value);
        expect(parentEvent['content'], {
          'via': [userDomain],
        });

        // AC:RL-subspace-create-with-parent/5 — связь пишется со стороны
        // родителя ОДНИМ m.space.child со state_key = созданная комната;
        // m.space.parent отдельным PUT не дублируется (он уже в initial_state);
        // createRoom идёт раньше PUT.
        final links = spaceLinkCalls();
        expect(links, [childPutPath(parent.value)]);
        final childBody = jsonDecode(
          FakeMatrixApi.calledEndpoints[childPutPath(parent.value)]!.single
              as String,
        );
        expect(childBody, {
          'via': [userDomain],
        });
        final order = FakeMatrixApi.calledEndpoints.keys.toList();
        expect(
          order.indexOf('/client/v3/createRoom'),
          lessThan(order.indexOf(childPutPath(parent.value))),
        );
      },
    );
  }

  test('провал m.space.child: созданный space покидается и забывается, '
      'исключение пробрасывается', () async {
    const parentId = '!company:example.invalid';
    // PUT не зарегистрирован → FakeMatrixApi отвечает M_UNRECOGNIZED/405 →
    // SDK бросает MatrixException.
    api.api['POST']!['/client/v3/rooms/$encodedCreated/forget'] = (_) => {};

    // AC:RL-subspace-create-with-parent/9 — компенсация орфана: без неё
    // space без входящего m.space.child клиент показал бы как вторую
    // «свою компанию».
    await expectLater(
      createSubspace(parent: space(parentId), name: 'Отдел'),
      throwsA(isA<MatrixException>()),
    );

    final calls = FakeMatrixApi.calledEndpoints.keys.toList();
    expect(calls, contains('/client/v3/rooms/$encodedCreated/leave'));
    expect(calls, contains('/client/v3/rooms/$encodedCreated/forget'));
    expect(
      calls.indexOf(childPutPath(parentId)),
      lessThan(calls.indexOf('/client/v3/rooms/$encodedCreated/leave')),
    );
  });

  test('провал самой компенсации не маскирует исходную ошибку', () async {
    const parentId = '!company:example.invalid';
    api.api['PUT']![childPutPath(parentId)] = (_) => {
      'errcode': 'M_FORBIDDEN',
      'error': 'child forbidden',
    };
    // leave/forget на !1234 не зарегистрированы как успешные: forget → 405.
    api.api['POST']!['/client/v3/rooms/$encodedCreated/leave'] = (_) => {
      'errcode': 'M_FORBIDDEN',
      'error': 'leave forbidden',
    };

    await expectLater(
      createSubspace(parent: space(parentId), name: 'Отдел'),
      throwsA(
        isA<MatrixException>().having(
          (e) => e.errorMessage,
          'исходная ошибка m.space.child',
          'child forbidden',
        ),
      ),
    );
  });
}
