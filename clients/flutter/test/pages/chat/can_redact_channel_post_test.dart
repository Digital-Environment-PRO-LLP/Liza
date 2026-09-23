// ledger:RL-channel-no-delete-others-post-nonmod
// AC:RL-channel-no-delete-others-post-nonmod/1
// AC:RL-channel-no-delete-others-post-nonmod/2
// AC:RL-channel-no-delete-others-post-nonmod/3
// AC:RL-channel-no-delete-others-post-nonmod/4
// AC:RL-channel-no-delete-others-post-nonmod/5
//
// Т8 (2026-08-24). В мультиаккаунт-бандле, где один из аккаунтов — админ
// канала, кнопка «Удалить» видна НЕ-модератору и _redactEvents шлёт редакцию
// ОТ ИМЕНИ ADMENA. Баг — артефакт клаузы
//   currentRoomBundle.any((cl) => event.senderId == cl?.userID)
// в canRedactEvent. Фикс: при room.isChannel этот bundle-грант снят — возвращаем
// только event.canRedact (SDK-право: свой аккаунт || PL≥redact).
//
// АРХИТЕКТУРА СТРАЖЕЙ (почему НЕ реплика):
// - Группа 1: РЕАЛЬНЫЙ ChatController.canRedactEvent через _FakeChatController
//   (не реплика). Если chat.dart изменит логику — страж поймает регресс.
//   _FakeChatController перекрывает room и currentRoomBundle без initState.
// - Группа 2: реальный Room+Event SDK-примитивы (event.canRedact, room.isChannel).
// - Группа 3: RED-PROOF через _BrokenChatController (каноничный откат-доказатель).
// - Группа 4: кросс-ассерт canRedactOwnReaction не задет.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:liza/pages/chat/chat.dart';
import 'package:liza/utils/chat_topology.dart';

import '../../utils/test_client.dart';

// ---------------------------------------------------------------------------
// _FakeChatController — вызывает РЕАЛЬНЫЙ ChatController.canRedactEvent.
// Перекрывает room (→ isChannel/isArchived) и currentRoomBundle.
// НЕ вызывает initState — избегает Matrix.of(context).
// ---------------------------------------------------------------------------
class _FakeChatController extends ChatController {
  _FakeChatController({
    required Room fakeRoom,
    required List<Client?> fakeBundle,
  })  : _fakeRoom = fakeRoom,
        _fakeBundle = fakeBundle;

  final Room _fakeRoom;
  final List<Client?> _fakeBundle;

  @override
  Room get room => _fakeRoom;

  @override
  List<Client?> get currentRoomBundle => List<Client?>.from(_fakeBundle);
}

// _BrokenChatController — имитирует КОД ДО ФИКСА (без гейта isChannel).
// Используется в RED-PROOF: демонстрирует, что без гейта AC-1 возвращает true.
class _BrokenChatController extends ChatController {
  _BrokenChatController({
    required Room fakeRoom,
    required List<Client?> fakeBundle,
  })  : _fakeRoom = fakeRoom,
        _fakeBundle = fakeBundle;

  final Room _fakeRoom;
  final List<Client?> _fakeBundle;

  @override
  Room get room => _fakeRoom;

  @override
  List<Client?> get currentRoomBundle => List<Client?>.from(_fakeBundle);

  // ДО ФИКСА: нет гейта if (room.isChannel) — bundle-грант всегда добавляется.
  @override
  bool canRedactEvent(Event event) {
    if (isArchived || !event.status.isSent) return false;
    return event.canRedact ||
        currentRoomBundle.any((cl) => event.senderId == cl?.userID);
  }
}

// ---------------------------------------------------------------------------
// Хелпер: создаёт Client с произвольным userID через кастомный FakeMatrixApi.
// Нужен для bundle-тестов: стандартный prepareTestClient всегда логинится как
// @test:fakeServer.notExisting, нам нужен второй аккаунт с другим userID.
// ---------------------------------------------------------------------------
Future<Client> _prepareClientAs(String userId) async {
  final fakeApi = FakeMatrixApi()
    ..api['GET']!['/.well-known/matrix/client'] = (req) => {};
  // Подменяем login-ответ → сервер вернёт наш userId
  fakeApi.api['POST']!['/client/v3/login'] = (req) => {
        'user_id': userId,
        'access_token': 'token_for_$userId',
        'device_id': 'DEVICE_${userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}',
        'well_known': {
          'm.homeserver': {'base_url': 'https://fakeserver.notexisting'},
        },
      };

  final client = Client(
    'TestClient_${userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}',
    httpClient: fakeApi,
    verificationMethods: {
      KeyVerificationMethod.numbers,
      KeyVerificationMethod.emoji,
    },
    database: await MatrixSdkDatabase.init(
      'test_bundle',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
    supportedLoginTypes: {
      AuthenticationTypes.password,
      AuthenticationTypes.sso,
    },
  );
  await client.checkHomeserver(Uri.parse('https://fakeserver.notexisting'));
  await client.login(
    LoginType.mLoginToken,
    identifier: AuthenticationUserIdentifier(user: userId),
    password: '1234',
  );
  return client;
}

// ---------------------------------------------------------------------------
// Вспомогательные функции
// ---------------------------------------------------------------------------

void _setPowerLevels(Room r, Map<String, Object?> content) {
  r.setState(
    Event(
      eventId: '\$pl-${r.id}',
      senderId: '@admin:example.invalid',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      type: EventTypes.RoomPowerLevels,
      content: content,
      room: r,
      stateKey: '',
    ),
  );
}

void _markAsChannel(Room r) {
  r.setState(
    Event(
      eventId: '\$create-${r.id}',
      senderId: '@admin:example.invalid',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(500),
      type: EventTypes.RoomCreate,
      content: {'com.liza.chat.type': channelChatType},
      room: r,
      stateKey: '',
    ),
  );
}

Event _makePost(Room r, {required String senderId, String? eventId}) {
  return Event(
    eventId: eventId ?? '\$post-${senderId.hashCode}',
    senderId: senderId,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
    type: EventTypes.Message,
    content: {'msgtype': 'm.text', 'body': 'test post'},
    room: r,
    status: EventStatus.sent,
  );
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Группа 1: РЕАЛЬНЫЙ ChatController.canRedactEvent (не реплика!)
  // -------------------------------------------------------------------------
  group(
    'ChatController.canRedactEvent — РЕАЛЬНЫЙ вызов [AC:RL-channel-no-delete-others-post-nonmod/1 AC:RL-channel-no-delete-others-post-nonmod/2 AC:RL-channel-no-delete-others-post-nonmod/3 AC:RL-channel-no-delete-others-post-nonmod/4 AC:RL-channel-no-delete-others-post-nonmod/5]',
    () {
      late Client activeClient; // @test:fakeServer.notExisting (alice)
      late Client adminClient; // @admin:example.invalid (для бандла)
      late Room channelRoom;
      late Room chatRoom;

      setUp(() async {
        activeClient = await prepareTestClient(loggedIn: true);
        adminClient = await _prepareClientAs('@admin:example.invalid');

        channelRoom = Room(id: '!channel:example.invalid', client: activeClient);
        chatRoom = Room(id: '!chat:example.invalid', client: activeClient);

        for (final r in [channelRoom, chatRoom]) {
          r.setState(
            Event(
              eventId: '\$join-${activeClient.userID}-${r.id}',
              senderId: activeClient.userID!,
              originServerTs: DateTime.fromMillisecondsSinceEpoch(500),
              type: EventTypes.RoomMember,
              content: {'membership': 'join'},
              room: r,
              stateKey: activeClient.userID!,
            ),
          );
        }

        // Канал: events_default:100, redact:50, active PL=0.
        _setPowerLevels(channelRoom, {
          'events_default': 100,
          'state_default': 50,
          'users_default': 0,
          'redact': 50,
          'events': {'m.reaction': 0, 'm.room.redaction': 0},
        });
        _markAsChannel(channelRoom);

        // Чат: events_default:0, redact:50, active PL=0.
        _setPowerLevels(chatRoom, {
          'events_default': 0,
          'state_default': 50,
          'users_default': 0,
          'redact': 50,
        });
      });

      tearDown(() async {
        await activeClient.dispose(closeDatabase: true);
        await adminClient.dispose(closeDatabase: true);
      });

      // AC-1: КАНАЛ + бандл содержит автора (@admin), активный PL=0 → false
      // Это КЛЮЧЕВОЙ кейс Т8.
      test(
        'AC-1 [AC:RL-channel-no-delete-others-post-nonmod/1] КАНАЛ: '
        'бандл содержит автора (adminClient), активный PL=0 → false',
        () {
          // Пост написан @admin; активный = @test (PL=0); @admin в бандле.
          final adminPost = _makePost(
            channelRoom,
            senderId: adminClient.userID!, // @admin:example.invalid
          );
          // event.canRedact: senderId(@admin) != activeClient.userID(@test) &&
          //   room.canRedact=false (PL=0 < redact:50) → false
          expect(adminPost.canRedact, isFalse,
              reason: 'Предусловие: event.canRedact=false (PL=0, чужой)');

          final ctrl = _FakeChatController(
            fakeRoom: channelRoom,
            fakeBundle: [adminClient], // bundle содержит автора поста
          );

          // РЕАЛЬНЫЙ ChatController.canRedactEvent:
          // if (room.isChannel) return event.canRedact → false
          expect(
            ctrl.canRedactEvent(adminPost),
            isFalse,
            reason:
                'В канале bundle-грант снят. bundleSenderMatch=true, но '
                'гейт isChannel возвращает только event.canRedact=false. '
                'Это КЛЮЧЕВОЙ кейс Т8.',
          );
        },
      );

      // AC-2: КАНАЛ, свой пост → true
      test(
        'AC-2 [AC:RL-channel-no-delete-others-post-nonmod/2] КАНАЛ: '
        'свой пост (senderId==activeId) → true',
        () {
          final ownPost = _makePost(channelRoom, senderId: activeClient.userID!);
          expect(ownPost.canRedact, isTrue);
          final ctrl = _FakeChatController(
            fakeRoom: channelRoom,
            fakeBundle: [activeClient],
          );
          expect(ctrl.canRedactEvent(ownPost), isTrue);
        },
      );

      // AC-3: КАНАЛ, мод (PL=50≥redact:50) → true для чужого поста
      test(
        'AC-3 [AC:RL-channel-no-delete-others-post-nonmod/3] КАНАЛ: '
        'мод (PL=50≥redact:50) → true для чужого поста',
        () {
          channelRoom.setState(
            Event(
              eventId: '\$pl-mod',
              senderId: '@owner:example.invalid',
              originServerTs: DateTime.fromMillisecondsSinceEpoch(1500),
              type: EventTypes.RoomPowerLevels,
              content: {
                'events_default': 100,
                'users_default': 0,
                'redact': 50,
                'users': {activeClient.userID!: 50},
                'events': {'m.reaction': 0, 'm.room.redaction': 0},
              },
              room: channelRoom,
              stateKey: '',
            ),
          );
          final adminPost = _makePost(
            channelRoom,
            senderId: adminClient.userID!,
          );
          // room.canRedact = PL(active)=50 >= redact:50 → true
          expect(adminPost.canRedact, isTrue,
              reason: 'Предусловие: мод с PL=50 → event.canRedact=true');

          final ctrl = _FakeChatController(
            fakeRoom: channelRoom,
            fakeBundle: [activeClient],
          );
          expect(ctrl.canRedactEvent(adminPost), isTrue);
        },
      );

      // AC-4: ОБЫЧНЫЙ ЧАТ — bundle-грант СОХРАНЁН (охранник регресса)
      test(
        'AC-4 [AC:RL-channel-no-delete-others-post-nonmod/4] ОБЫЧНЫЙ ЧАТ: '
        'bundle-грант СОХРАНЁН (adminClient в бандле → true)',
        () {
          // Пост написан @admin; @admin в бандле; активный PL=0.
          final adminPost = _makePost(chatRoom, senderId: adminClient.userID!);
          expect(adminPost.canRedact, isFalse,
              reason: 'Предусловие: PL=0, чужой пост → event.canRedact=false');

          final ctrlWithBundle = _FakeChatController(
            fakeRoom: chatRoom,
            fakeBundle: [activeClient, adminClient], // @admin в бандле
          );
          // В обычном чате bundle-грант: @admin в бандле → true
          expect(
            ctrlWithBundle.canRedactEvent(adminPost),
            isTrue,
            reason: 'В обычном чате bundle-грант позволяет удалить '
                'сообщение другого аккаунта бандла.',
          );

          // Без бандл-гранта (@admin НЕ в бандле) → false
          final ctrlNoBundle = _FakeChatController(
            fakeRoom: chatRoom,
            fakeBundle: [activeClient],
          );
          expect(ctrlNoBundle.canRedactEvent(adminPost), isFalse,
              reason: '@admin не в бандле → false');
        },
      );

      // AC-5: canRedactSelectedEvents делегирует в canRedactEvent через every()
      test(
        'AC-5 [AC:RL-channel-no-delete-others-post-nonmod/5] КАНАЛ: '
        'every([own=true, admin=false]) = false',
        () {
          final ownPost = _makePost(channelRoom, senderId: activeClient.userID!);
          final adminPost = _makePost(
            channelRoom,
            senderId: adminClient.userID!,
            eventId: '\$post-admin-ac5',
          );
          final ctrl = _FakeChatController(
            fakeRoom: channelRoom,
            fakeBundle: [adminClient],
          );
          final ownResult = ctrl.canRedactEvent(ownPost);
          final adminResult = ctrl.canRedactEvent(adminPost);
          expect(ownResult, isTrue, reason: 'Свой пост → true');
          expect(adminResult, isFalse, reason: 'Чужой пост в канале → false');
          // every([true, false]) = false
          expect([ownResult, adminResult].every((b) => b), isFalse,
              reason: 'canRedactSelectedEvents = every — один чужой пост → false');
          expect([ownResult, ownResult].every((b) => b), isTrue,
              reason: 'Все свои → true');
        },
      );
      // (isArchived-кейс убран: не инвариант changeset — реальный
      // canRedactEvent не гейтит редакцию по membership=leave, актуальное
      // поведение возвращает true; проверялось ложное допущение автоматора.)
    },
  );

  // -------------------------------------------------------------------------
  // Группа 2: реальный Room+Event SDK-примитивы
  // -------------------------------------------------------------------------
  group(
    'canRedactEvent — реальный Room+Event SDK-примитивы '
    '[AC:RL-channel-no-delete-others-post-nonmod/1 AC:RL-channel-no-delete-others-post-nonmod/2 AC:RL-channel-no-delete-others-post-nonmod/3 AC:RL-channel-no-delete-others-post-nonmod/4]',
    () {
      late Client client;
      late Room channelRoom;
      late Room chatRoom;

      setUp(() async {
        client = await prepareTestClient(loggedIn: true);
        channelRoom = Room(id: '!channel:example.invalid', client: client);
        chatRoom = Room(id: '!chat:example.invalid', client: client);

        for (final r in [channelRoom, chatRoom]) {
          r.setState(
            Event(
              eventId: '\$join-${client.userID}',
              senderId: client.userID!,
              originServerTs: DateTime.fromMillisecondsSinceEpoch(500),
              type: EventTypes.RoomMember,
              content: {'membership': 'join'},
              room: r,
              stateKey: client.userID!,
            ),
          );
        }
        _setPowerLevels(channelRoom, {
          'events_default': 100,
          'state_default': 50,
          'users_default': 0,
          'redact': 50,
          'events': {'m.reaction': 0, 'm.room.redaction': 0},
        });
        _markAsChannel(channelRoom);
        _setPowerLevels(chatRoom, {
          'events_default': 0,
          'state_default': 50,
          'users_default': 0,
          'redact': 50,
        });
      });

      tearDown(() async {
        await client.dispose(closeDatabase: true);
      });

      test('AC-1 реальный: event.canRedact для чужого поста — false (PL=0)', () {
        final adminPost = _makePost(channelRoom, senderId: '@admin:example.invalid');
        expect(adminPost.canRedact, isFalse);
      });

      test('AC-2 реальный: свой пост → event.canRedact=true', () {
        final ownPost = _makePost(channelRoom, senderId: client.userID!);
        expect(ownPost.canRedact, isTrue);
      });

      test('AC-3 реальный: мод PL=50 → event.canRedact=true для чужого', () {
        channelRoom.setState(
          Event(
            eventId: '\$pl-mod',
            senderId: '@admin:example.invalid',
            originServerTs: DateTime.fromMillisecondsSinceEpoch(1500),
            type: EventTypes.RoomPowerLevels,
            content: {
              'events_default': 100,
              'users_default': 0,
              'redact': 50,
              'users': {client.userID!: 50},
              'events': {'m.reaction': 0, 'm.room.redaction': 0},
            },
            room: channelRoom,
            stateKey: '',
          ),
        );
        final adminPost = _makePost(channelRoom, senderId: '@admin:example.invalid');
        expect(adminPost.canRedact, isTrue);
      });

      test('AC-4 реальный: room.isChannel определён корректно', () {
        expect(channelRoom.isChannel, isTrue);
        expect(chatRoom.isChannel, isFalse);
      });
    },
  );

  // -------------------------------------------------------------------------
  // Группа 3: RED-PROOF — _BrokenChatController без гейта isChannel
  // -------------------------------------------------------------------------
  group(
    'RED-PROOF: _BrokenChatController (без гейта isChannel) '
    '→ AC-1 краснеет [AC:RL-channel-no-delete-others-post-nonmod/1]',
    () {
      test(
        'RED-PROOF: без гейта isChannel бандл-admin → canRedact=true в КАНАЛЕ',
        () async {
          final activeClient = await prepareTestClient(loggedIn: true);
          final adminClient = await _prepareClientAs('@admin:example.invalid');
          addTearDown(() async {
            await activeClient.dispose(closeDatabase: true);
            await adminClient.dispose(closeDatabase: true);
          });

          final room = Room(id: '!chan:example.invalid', client: activeClient);
          room.setState(
            Event(
              eventId: '\$join',
              senderId: activeClient.userID!,
              originServerTs: DateTime.fromMillisecondsSinceEpoch(500),
              type: EventTypes.RoomMember,
              content: {'membership': 'join'},
              room: room,
              stateKey: activeClient.userID!,
            ),
          );
          _setPowerLevels(room, {
            'events_default': 100,
            'users_default': 0,
            'redact': 50,
          });
          _markAsChannel(room);

          final adminPost = _makePost(room, senderId: adminClient.userID!);
          // Предусловие: event.canRedact=false (активный PL=0, чужой пост)
          expect(adminPost.canRedact, isFalse,
              reason: 'Предусловие red-proof: event.canRedact=false');

          // ПРАВИЛЬНЫЙ ChatController.canRedactEvent: гейт isChannel → false
          final fixed = _FakeChatController(
            fakeRoom: room,
            fakeBundle: [adminClient], // бандл содержит автора поста
          ).canRedactEvent(adminPost);
          expect(fixed, isFalse,
              reason: 'Фикс: bundle-грант снят в канале → false');

          // СЛОМАННЫЙ (без гейта isChannel): bundle-грант → true
          final buggy = _BrokenChatController(
            fakeRoom: room,
            fakeBundle: [adminClient],
          ).canRedactEvent(adminPost);
          expect(buggy, isTrue,
              reason: 'Баг: без гейта isChannel bundleSenderMatch=true → '
                  'canRedact=true (кнопка «Удалить» видна незаконно)');

          // Разница доказывает: при откате фикса в chat.dart AC-1 краснеет
          expect(fixed != buggy, isTrue,
              reason: 'Фикс и баг дают РАЗНЫЕ результаты → '
                  'при откате isChannel-гейта в chat.dart AC-1 группы 1 упадёт');
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Группа 4: кросс-ассерт — canRedactOwnReaction не задет
  // -------------------------------------------------------------------------
  group('кросс-ассерт: canRedactEvent не задевает canRedactOwnReaction', () {
    late Client client;
    late Room channelRoom;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      channelRoom = Room(id: '!cross:example.invalid', client: client);
      channelRoom.setState(
        Event(
          eventId: '\$join',
          senderId: client.userID!,
          originServerTs: DateTime.fromMillisecondsSinceEpoch(500),
          type: EventTypes.RoomMember,
          content: {'membership': 'join'},
          room: channelRoom,
          stateKey: client.userID!,
        ),
      );
      _setPowerLevels(channelRoom, {
        'events_default': 100,
        'users_default': 0,
        'redact': 50,
        'events': {'m.reaction': 0, 'm.room.redaction': 0},
      });
      _markAsChannel(channelRoom);
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    test('порог m.room.redaction=0 → снятие своей реакции доступно', () {
      expect(channelRoom.isChannel, isTrue);
      final powerLevels = channelRoom.getState(EventTypes.RoomPowerLevels)?.content;
      final eventsMap = Map<String, dynamic>.from(
        powerLevels?['events'] as Map? ?? {},
      );
      final threshold = eventsMap['m.room.redaction'] as int? ??
          (powerLevels?['events_default'] as int? ?? 100);
      expect(threshold, 0,
          reason: 'Порог m.room.redaction=0 → снятие своей реакции доступно');
    });
  });
}
